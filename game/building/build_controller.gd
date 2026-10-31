class_name BuildController
extends Node
## Commits validated placement commands; occupancy belongs to the world registry.

signal built(option: BuildOption, cell: Vector2i)
signal changed
var prices: PriceService
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

func footprint_at(option: BuildOption, cell: Vector2i) -> Array[Vector2i]:
	return _footprint(option, cell)

func check(option: BuildOption, cell: Vector2i) -> PlacementCheck:
	var placement: PlacementCheck = placement_check(option, cell)
	if not placement.allowed():
		return placement
	if not inventory.can_afford_all(price(option)):
		return PlacementCheck.result(PlacementCheck.Code.RESOURCES)
	if option is SceneBuildOption and option.spawn_count > 0:
		var food: ResourceType = inventory.type_by_id(&"food")
		if inventory.available(food) - price_amount(price(option), food) < option.spawn_count:
			return PlacementCheck.result(PlacementCheck.Code.SPAWN_FOOD)
		var escape_units: float = route_service.food_field().cost(cell)
		var energy: float = escape_units * route_service.cell_size() / option.spawn_speed * 2.25 + AntNeeds.MEAL_SECONDS + AntNeeds.SAFETY_MARGIN
		if energy > AntNeeds.CAPACITY:
			return PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
	return PlacementCheck.new()

## Geometry-only check for a draft. The final command validates its entire budget and grid.
func placement_check(option: BuildOption, cell: Vector2i, removed: Array[Building] = []) -> PlacementCheck:
	if _committing:
		return PlacementCheck.result(PlacementCheck.Code.BUSY)
	if option == null or not options.has(option):
		return PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
	if option is TileBuildOption:
		var tile: TileBuildOption = option as TileBuildOption
		var source: TileSetAtlasSource = map.tile_set.get_source(tile.source_id) as TileSetAtlasSource if map.tile_set.has_source(tile.source_id) else null
		if source == null or not source.has_tile(tile.atlas_coords) or not source.has_alternative_tile(tile.atlas_coords, tile.alternative_tile):
			return PlacementCheck.result(PlacementCheck.Code.INVALID_TILE)
		if map.get_cell_source_id(cell) == tile.source_id and map.get_cell_atlas_coords(cell) == tile.atlas_coords:
			return PlacementCheck.result(PlacementCheck.Code.ALREADY_PLACED)
	elif option is SceneBuildOption:
		if option.scene == null or option.occupied_cells.is_empty() or not option.occupied_cells.has(Vector2i.ZERO) or option.spawn_count < 0 or option.spawn_speed <= 0.0:
			return PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
		if option.blocks_movement and option.entry_offsets.is_empty():
			return PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
	else:
		return PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
	for target in _footprint(option, cell):
		if map.get_cell_source_id(target) == -1:
			return PlacementCheck.result(PlacementCheck.Code.OUTSIDE_MAP)
		var terrain: TileData = map.get_cell_tile_data(target)
		if map.tile_set.get_custom_data_layer_by_name("buildable") >= 0 and not terrain.get_custom_data("buildable"):
			return PlacementCheck.result(PlacementCheck.Code.UNBUILDABLE)
		if not route_service.walkable(target) and not removed.has(registry.at(target)):
			return PlacementCheck.result(PlacementCheck.Code.IMPASSABLE)
		if registry.at(target) != null and not removed.has(registry.at(target)) and (option is SceneBuildOption or not option.allow_when_occupied):
			return PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
		if not option.allow_when_occupied and population != null:
			for ant in population.agents():
				if route_service.world_to_cell(ant.global_position) == target:
					return PlacementCheck.result(PlacementCheck.Code.ANT_PRESENT)
	return PlacementCheck.new()

func can_build(option: BuildOption, cell: Vector2i) -> bool:
	return check(option, cell).allowed()

func try_build(option: BuildOption, cell: Vector2i) -> bool:
	return try_build_batch({cell: option})

## All placements either commit together or leave stock, buildings, and navigation untouched.
func try_build_batch(commands: Dictionary[Vector2i, BuildOption]) -> bool:
	var plan: Array[BuildCommand] = []
	for cell in commands: plan.append(BuildCommand.create(cell, commands[cell]))
	return try_build_plan(plan)

func try_build_plan(commands: Array[BuildCommand]) -> bool:
	last_result = PlacementCheck.new()
	if _committing:
		last_result = PlacementCheck.result(PlacementCheck.Code.BUSY)
		return false
	if commands.is_empty():
		return true
	var removed: Array[Building] = []
	var placements: Array[BuildCommand] = []
	for command in commands:
		if command == null:
			last_result = PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
			return false
		if command.is_removal():
			var building: Building = command.removed_building
			if not is_instance_valid(building) or registry.at(command.cell) != building or removed.has(building):
				last_result = PlacementCheck.result(PlacementCheck.Code.NO_BUILDING)
				return false
			removed.append(building)
		else:
			placements.append(command)
	var costs: Array[ResourceAmount] = []
	var cells: Array[Vector2i] = []
	for building in removed: cells.append_array(building.footprint())
	var occupied: Dictionary[Vector2i, bool] = {}
	var terrain: Dictionary[Vector2i, bool] = {}
	var candidates: Array[Building] = []
	var spawn_count := 0
	for command in placements:
		var cell: Vector2i = command.cell
		var option: BuildOption = command.option
		last_result = placement_check(option, cell, removed)
		if not last_result.allowed():
			break
		var layer: Dictionary[Vector2i, bool] = terrain if option is TileBuildOption else occupied
		for target in _footprint(option, cell):
			if layer.has(target):
				last_result = PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
				break
			cells.append(target)
			layer[target] = true
		if not last_result.allowed():
			break
		pass # The complete sequential quote is computed once below.
		if option is SceneBuildOption:
			var candidate: Node = option.scene.instantiate()
			if not candidate is Building:
				candidate.free()
				last_result = PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
				break
			var building: Building = candidate as Building
			candidates.append(building)
			if not building.setup(cell, option):
				last_result = PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
				break
			if building is House:
				spawn_count += building.capacity
	if last_result.allowed(): costs = prices.quote_plan(placements) if prices != null else _base_plan_price(placements)
	if last_result.allowed() and not inventory.can_afford_all(costs):
		last_result = PlacementCheck.result(PlacementCheck.Code.RESOURCES)
	if last_result.allowed():
		var food: ResourceType = inventory.type_by_id(&"food")
		var food_cost := 0
		for cost in costs:
			if food != null and cost.type.id == food.id: food_cost += cost.amount
		if inventory.available(food) - food_cost < spawn_count:
			last_result = PlacementCheck.result(PlacementCheck.Code.SPAWN_FOOD)
	if last_result.allowed() and not _batch_preserves_escape(placements, candidates, removed):
		last_result = PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
	if not last_result.allowed():
		for candidate in candidates: candidate.free()
		return false
	# No awaits or notifications until the world and inventory agree.
	_committing = true
	inventory.begin_update()
	if not inventory.try_spend_all(costs):
		for candidate in candidates: candidate.free()
		last_result = PlacementCheck.result(PlacementCheck.Code.RESOURCES)
		_committing = false
		inventory.end_update()
		return false
	for command in placements:
		var cell: Vector2i = command.cell
		var option: BuildOption = command.option
		if option is TileBuildOption:
			map.set_cell(cell, option.source_id, option.atlas_coords, option.alternative_tile)
	for building in removed:
		_refund_for_demolish(building.option)
		if prices != null: prices.record(GameEvents.Kind.BUILDING_DEMOLISHED, building.option.id if building.option != null else &"initial")
		building.demolish()
		building.free()
	var blocked: Array[Vector2i] = registry.blocked_cells()
	for candidate in candidates:
		if candidate.option.blocks_movement:
			blocked.append_array(candidate.footprint())
	# New residents must see the final grid when the registry announces their home.
	route_service.update_cells(cells, blocked)
	for candidate in candidates:
		candidate.position = buildings.to_local(route_service.cell_to_world(candidate.cell))
		buildings.add_child(candidate)
		registry.register(candidate)
	_committing = false
	inventory.end_update()
	for command in placements:
		if prices != null: prices.record(GameEvents.Kind.BUILDING_BUILT, command.option.id)
		built.emit(command.option, command.cell)
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
	if not _can_remove_food(building):
		last_result = PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
		return false
	_committing = true
	inventory.begin_update()
	_refund_for_demolish(building.option)
	var changed_cells: Array[Vector2i] = building.footprint()
	building.demolish()
	building.free()
	route_service.update_cells(changed_cells, registry.blocked_cells())
	_committing = false
	inventory.end_update()
	changed.emit()
	return true

## Returns part of the build cost. Buildings without an option (placed in the scene) refund nothing.
func _refund_for_demolish(option: BuildOption) -> void:
	if option == null:
		return
	for type in inventory.registered_types():
		var amount: int = floori(option.cost_amount(type) * DEMOLISH_REFUND_RATIO)
		if amount > 0:
			inventory.add(type, amount)

func _footprint(option: BuildOption, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if option is SceneBuildOption:
		for offset in option.occupied_cells:
			if not cells.has(origin + offset):
				cells.append(origin + offset)
	else:
		cells.append(origin)
	return cells

func _batch_preserves_escape(commands: Array[BuildCommand], candidates: Array[Building], removed: Array[Building] = []) -> bool:
	var values: Dictionary[Vector2i, float] = {}
	var needs_check := not removed.is_empty()
	for building in removed:
		for cell in building.footprint():
			var data: TileData = map.get_cell_tile_data(cell)
			values[cell] = float(data.get_custom_data("move_cost")) if data != null else 0.0
	for candidate in candidates:
		needs_check = needs_check or candidate is House or candidate.option.blocks_movement
	for command in commands:
		var cell: Vector2i = command.cell
		var option: BuildOption = command.option
		if option is TileBuildOption:
			var source: TileSetAtlasSource = map.tile_set.get_source(option.source_id) as TileSetAtlasSource
			var value: float = float(source.get_tile_data(option.atlas_coords, option.alternative_tile).get_custom_data("move_cost"))
			values[cell] = value
			needs_check = needs_check or value <= 0.0 or value > route_service.entry_cost(cell)
	for candidate in candidates:
		if candidate.option.blocks_movement:
			for target in candidate.footprint(): values[target] = 0.0
	if not needs_check:
		return true
	var preview: TileGrid = route_service.snapshot().with_costs(values)
	var foods: Array[Vector2i] = []
	for canteen in registry.canteens():
		if not removed.has(canteen): foods.append_array(canteen.entry_cells())
	for candidate in candidates:
		if candidate is Canteen: foods.append_array(candidate.entry_cells())
	var field: NavigationField = GridSearch.build(preview, foods, true)
	for candidate in candidates:
		var nearest_food := INF
		for entry in candidate.entry_cells():
			if not preview.walkable(entry) or not is_finite(field.cost(entry)):
				return false
			nearest_food = minf(nearest_food, field.cost(entry))
		if candidate is House:
			var energy: float = nearest_food * route_service.cell_size() / candidate.option.spawn_speed * 2.25 + AntNeeds.MEAL_SECONDS + AntNeeds.SAFETY_MARGIN
			if energy > AntNeeds.CAPACITY:
				return false
	return _agents_can_escape(field, removed)

func _agents_can_escape(field: NavigationField, removed: Array[Building] = []) -> bool:
	for ant in population.agents():
		if removed.has(ant.home): continue
		var cost: float = field.cost(route_service.world_to_cell(ant.global_position))
		var energy: float = cost * route_service.cell_size() / (ant.speed * TripPlanner.CARRY_SPEED_RATIO) + AntNeeds.MEAL_SECONDS
		if not ant.needs.can_afford(energy):
			return false
	return true

func _can_remove_food(building: Building) -> bool:
	if not building is Canteen:
		return true
	var remaining: Array[Vector2i] = []
	for canteen in registry.canteens():
		if canteen != building:
			remaining.append_array(canteen.entry_cells())
	return _agents_can_escape(GridSearch.build(route_service.snapshot(), remaining, true))

func price(option: BuildOption) -> Array[ResourceAmount]:
	return prices.quote(option) if prices != null else option.costs

static func price_amount(costs: Array[ResourceAmount], type: ResourceType) -> int:
	var result := 0
	for entry in costs:
		if entry != null and entry.type != null and type != null and entry.type.id == type.id: result += entry.amount
	return result

func _base_plan_price(commands: Array[BuildCommand]) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	for command in commands:
		if not command.is_removal(): result.append_array(command.option.costs)
	return result
