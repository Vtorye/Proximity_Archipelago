class_name BuildController
extends Node
## Commits validated placement commands; occupancy belongs to the world registry.

signal built(option: BuildOption, cell: Vector2i)
signal changed
var registry: BuildingRegistry
var population: ColonyPopulation
var map: TileMapLayer
var buildings: Node2D
var inventory: WorldInventory
var route_service: RouteService
var options: Array[BuildOption] = []
var _committing := false
var last_result := PlacementCheck.new()

func configure(tile_map: TileMapLayer, building_root: Node2D, stock: WorldInventory, catalog: Array[BuildOption]) -> void:
	map = tile_map
	buildings = building_root
	inventory = stock
	options = catalog.duplicate()

## Existing homes and workplaces reserve their cells, but remain accessible.
func reserve_existing(node: Node2D) -> void:
	if node is Building:
		registry.register(node)

func blocked_cells() -> Array[Vector2i]:
	return registry.blocked_cells()

func check(option: BuildOption, cell: Vector2i) -> PlacementCheck:
	if _committing:
		return PlacementCheck.result(PlacementCheck.Code.BUSY)
	if option == null or not options.has(option):
		return PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
	if not inventory.can_afford(option.cost):
		return PlacementCheck.result(PlacementCheck.Code.RESOURCES)
	if option is TileBuildOption:
		var tile: TileBuildOption = option as TileBuildOption
		var source: TileSetAtlasSource = map.tile_set.get_source(tile.source_id) as TileSetAtlasSource if map.tile_set.has_source(tile.source_id) else null
		if source == null or not source.has_tile(tile.atlas_coords) or not source.has_alternative_tile(tile.atlas_coords, tile.alternative_tile):
			return PlacementCheck.result(PlacementCheck.Code.INVALID_TILE)
		if map.get_cell_source_id(cell) == tile.source_id and map.get_cell_atlas_coords(cell) == tile.atlas_coords:
			return PlacementCheck.result(PlacementCheck.Code.ALREADY_PLACED)
	elif option is SceneBuildOption:
		if option.scene == null or option.occupied_cells.is_empty() or not option.occupied_cells.has(Vector2i.ZERO):
			return PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
		if option.spawn_count > 0:
			if inventory.available(inventory.type_by_id(&"food")) < option.spawn_count:
				return PlacementCheck.result(PlacementCheck.Code.SPAWN_FOOD)
			var escape_units: float = route_service.food_field().cost(cell)
			var energy: float = escape_units * route_service.cell_size() / option.spawn_speed * 2.25 + AntNeeds.MEAL_SECONDS + AntNeeds.SAFETY_MARGIN
			if energy > AntNeeds.CAPACITY:
				return PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
		if option.blocks_movement and option.entry_offsets.is_empty():
			return PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
	else:
		return PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
	for target in _footprint(option, cell):
		if map.get_cell_source_id(target) == -1 or not route_service.walkable(target):
			return PlacementCheck.result(PlacementCheck.Code.OUTSIDE_MAP)
		if option is SceneBuildOption and registry.at(target) != null:
			return PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
		if not option.allow_when_occupied and population != null:
			for ant in population.agents():
				if route_service.world_to_cell(ant.global_position) == target:
					return PlacementCheck.result(PlacementCheck.Code.ANT_PRESENT)
	return PlacementCheck.new()

func can_build(option: BuildOption, cell: Vector2i) -> bool:
	return check(option, cell).allowed()

func try_build(option: BuildOption, cell: Vector2i) -> bool:
	last_result = check(option, cell)
	if not last_result.allowed():
		return false
	var instance: Building
	if option is SceneBuildOption:
		var candidate: Node = option.scene.instantiate()
		if not candidate is Building:
			candidate.free()
			last_result = PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
			return false
		instance = candidate as Building
		if not instance.setup(cell, option):
			instance.free()
			last_result = PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
			return false
	if not _preserves_escape(option, cell):
		if instance != null:
			instance.free()
		last_result = PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
		return false
	# No awaits or notifications until the world and inventory agree.
	_committing = true
	inventory.begin_update()
	if not inventory.try_spend(option.cost):
		if instance != null:
			instance.free()
		_committing = false
		inventory.end_update()
		return false
	if option is TileBuildOption:
		map.set_cell(cell, option.source_id, option.atlas_coords, option.alternative_tile)
	else:
		instance.position = buildings.to_local(route_service.cell_to_world(cell))
		buildings.add_child(instance)
		registry.register(instance)
	route_service.rebuild(registry.blocked_cells())
	_committing = false
	inventory.end_update()
	built.emit(option, cell)
	changed.emit()
	return true

## Share of the build cost returned on demolition. 0 = no refund; raise to enable refunds.
const DEMOLISH_REFUND_RATIO := 0.0

func demolition_check(cell: Vector2i) -> PlacementCheck:
	if _committing:
		return PlacementCheck.result(PlacementCheck.Code.BUSY)
	var building: Building = registry.at(cell)
	if building is Canteen and registry.canteens().size() <= 1 and population.count() > 0:
		return PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
	return PlacementCheck.result(PlacementCheck.Code.OK if building != null else PlacementCheck.Code.NO_BUILDING)

## Demolishes the building on the cell. No confirmation; residents die with DEMOLISHED.
## The presentation requests confirmation; this command has no UI dependencies.
func demolish_at(cell: Vector2i) -> bool:
	last_result = demolition_check(cell)
	if not last_result.allowed():
		return false
	var building: Building = registry.at(cell)
	# Removing the last feeding point while ants are alive would invalidate every safe plan.
	if building is Canteen and registry.canteens().size() <= 1 and population.count() > 0:
		last_result = PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
		return false
	_committing = true
	inventory.begin_update()
	_refund_for_demolish(building.option)
	building.demolish()
	building.free()
	route_service.rebuild(registry.blocked_cells())
	_committing = false
	inventory.end_update()
	changed.emit()
	return true

## Returns part of the build cost. Buildings without an option (placed in the scene) refund nothing.
func _refund_for_demolish(option: BuildOption) -> void:
	if option != null and option.cost != null:
		var amount: int = floori(option.cost.amount * DEMOLISH_REFUND_RATIO)
		if amount > 0:
			inventory.add(option.cost.type, amount)

func _footprint(option: BuildOption, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if option is SceneBuildOption:
		for offset in option.occupied_cells:
			if not cells.has(origin + offset):
				cells.append(origin + offset)
	else:
		cells.append(origin)
	return cells

func _preserves_escape(option: BuildOption, cell: Vector2i) -> bool:
	if not option is SceneBuildOption or not option.blocks_movement:
		return true
	var blocked: Array[Vector2i] = registry.blocked_cells()
	blocked.append_array(_footprint(option, cell))
	var preview := TileGrid.new()
	preview.setup(map, blocked)
	var foods: Array[Vector2i] = []
	for canteen in registry.canteens():
		foods.append_array(canteen.entry_cells())
	var field: NavigationField = GridSearch.build(preview, foods, true)
	for offset in option.entry_offsets:
		if not preview.walkable(cell + offset) or not is_finite(field.cost(cell + offset)):
			return false
	for ant in population.agents():
		var cost: float = field.cost(route_service.world_to_cell(ant.global_position))
		var energy: float = cost * route_service.cell_size() / (ant.speed * TripPlanner.CARRY_SPEED_RATIO) + AntNeeds.MEAL_SECONDS
		if not ant.needs.can_afford(energy):
			return false
	return true

