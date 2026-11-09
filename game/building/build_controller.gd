class_name BuildController
extends Node
## Commits validated placement commands; occupancy belongs to the world registry.

signal built(option: BuildOption, cell: Vector2i)
signal changed

@export var catalog: BuildCatalog
@export var physical_construction := true
var construction: ConstructionService
var terrain: TerrainRules
var prices: PriceService
var registry: BuildingRegistry
var population: ColonyPopulation
var logistics: ColonyLogistics
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

func initial_options() -> Array[BuildOption]:
	if catalog == null:
		return []
	return catalog.options.duplicate()

func blocked_cells() -> Array[Vector2i]:
	return registry.blocked_cells()

func footprint_at(option: BuildOption, cell: Vector2i) -> Array[Vector2i]:
	return _footprint(option, cell)

func check(option: BuildOption, cell: Vector2i) -> PlacementCheck:
	var placement: PlacementCheck = placement_check(option, cell)
	if not placement.allowed():
		return placement
	var command := BuildCommand.create(cell, option)
	return PlacementCheck.result(_funding({command: price(option, cell)}, []).code)

## Geometry-only check for a draft. The final command validates its entire budget and grid.
func placement_check(option: BuildOption, cell: Vector2i, removed: Array[Building] = []) -> PlacementCheck:
	if _committing:
		return PlacementCheck.result(PlacementCheck.Code.BUSY)
	if option == null or not options.has(option):
		return PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
	if construction != null and construction.at(cell, option is TileBuildOption) != null and not removed.has(construction.at(cell, option is TileBuildOption)):
		return PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
	if terrain != null and terrain.restricts(option, cell):
		return PlacementCheck.result(PlacementCheck.Code.SOIL_RESTRICTED)
	if option is WorkplaceUpgradeOption:
		var workplace := registry.at(cell) as Workplace
		if workplace == null or removed.has(workplace) or not workplace.accepts_improvement(option):
			return PlacementCheck.result(PlacementCheck.Code.RESOURCE_SITE)
		return PlacementCheck.new()
	if option is TileBuildOption:
		var tile: TileBuildOption = option as TileBuildOption
		var source: TileSetAtlasSource = map.tile_set.get_source(tile.source_id) as TileSetAtlasSource if map.tile_set.has_source(tile.source_id) else null
		if source == null or not source.has_tile(tile.atlas_coords) or not source.has_alternative_tile(tile.atlas_coords, tile.alternative_tile):
			return PlacementCheck.result(PlacementCheck.Code.INVALID_TILE)
		var key := Vector4i(tile.source_id, tile.atlas_coords.x, tile.atlas_coords.y, tile.alternative_tile)
		var result: Vector4i = map.result_key(cell, key) if map is TerrainMap else key
		if map.get_cell_source_id(cell) == result.x and map.get_cell_atlas_coords(cell) == Vector2i(result.y, result.z) and map.get_cell_alternative_tile(cell) == result.w:
			return PlacementCheck.result(PlacementCheck.Code.ALREADY_PLACED)
	elif option is SceneBuildOption:
		if option.scene == null or option.occupied_cells.is_empty() or not option.occupied_cells.has(Vector2i.ZERO) or option.spawn_count < 0 or option.spawn_speed <= 0.0:
			return PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
		if (option.blocks_movement or option.requires_water) and option.entry_offsets.is_empty():
			return PlacementCheck.result(PlacementCheck.Code.INVALID_BUILDING)
	else:
		return PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
	var water_site: bool = option is SceneBuildOption and option.requires_water
	for target in _footprint(option, cell):
		if map.get_cell_source_id(target) == -1:
			return PlacementCheck.result(PlacementCheck.Code.OUTSIDE_MAP)
		if terrain != null and terrain.restricts(option, target):
			return PlacementCheck.result(PlacementCheck.Code.SOIL_RESTRICTED)
		var tile_data: TileData = map.get_cell_tile_data(target)
		if water_site:
			var surface: TerrainType = map.surface_at(target) if map is TerrainMap else null
			if surface == null or surface.kind != TerrainType.Kind.WATER:
				return PlacementCheck.result(PlacementCheck.Code.WATER_REQUIRED)
		else:
			if map.tile_set.get_custom_data_layer_by_name("buildable") >= 0 and not tile_data.get_custom_data("buildable"):
				return PlacementCheck.result(PlacementCheck.Code.UNBUILDABLE)
			if not route_service.walkable(target) and not removed.has(registry.at(target)):
				return PlacementCheck.result(PlacementCheck.Code.IMPASSABLE)
		if registry.at(target) != null and not removed.has(registry.at(target)) and (option is SceneBuildOption or not option.allow_when_occupied):
			return PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
		if not option.allow_when_occupied and population != null:
			for ant in population.agents():
				if route_service.world_to_cell(ant.global_position) == target:
					return PlacementCheck.result(PlacementCheck.Code.ANT_PRESENT)
	if water_site and not option.entries_at(cell).any(route_service.walkable):
		return PlacementCheck.result(PlacementCheck.Code.SHORE_REQUIRED)
	return PlacementCheck.new()

func can_build(option: BuildOption, cell: Vector2i) -> bool:
	return check(option, cell).allowed()

func funding_check(commands: Array[BuildCommand], removed: Array[Building]) -> PlacementCheck:
	return PlacementCheck.result(_funding(_quote_orders(commands), removed).code)

func _quote_orders(commands: Array[BuildCommand]) -> Dictionary:
	if prices != null:
		return prices.quote_commands(commands)
	var quotes := {}
	for command in commands:
		if not command.is_removal():
			quotes[command] = command.option.costs
	return quotes

func _funding(quotes: Dictionary, removed: Array[Building]) -> Dictionary:
	var costs: Array[ResourceAmount] = []
	for quote: Array in quotes.values():
		costs.append_array(quote)
	if not inventory.can_afford_all(costs, true, true):
		return {"code": PlacementCheck.Code.RESOURCES}
	var allocations := {}
	if construction != null:
		var planned := {}
		for command: BuildCommand in quotes:
			if not ConstructionService.needs_builders(command.option, quotes[command]):
				continue
			var entries: Array[Vector2i] = [command.cell]
			if command.option is SceneBuildOption:
				entries = command.option.entries_at(command.cell)
			var sources: Array[House] = logistics.construction_sources(entries, removed)
			var crates: Variant = inventory.allocate_build_materials(quotes[command], logistics.main_nest, sources, planned)
			if crates == null:
				return {"code": PlacementCheck.Code.NO_BUILD_SUPPLY}
			allocations[command] = crates
	return {"code": PlacementCheck.Code.OK, "crates": allocations, "costs": costs}

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
	var removed_improvements: Array[Workplace] = []
	var placements: Array[BuildCommand] = []
	for command in commands:
		if command == null:
			last_result = PlacementCheck.result(PlacementCheck.Code.INVALID_OPTION)
			return false
		if command.is_removal():
			var building: Building = command.removed_building
			if not is_instance_valid(building) or demolition_target(command.cell) != building or removed.has(building) or (building is Workplace and removed_improvements.has(building)):
				last_result = PlacementCheck.result(PlacementCheck.Code.NO_BUILDING)
				return false
			if building is House and logistics != null and not logistics.can_remove(building):
				last_result = PlacementCheck.result(PlacementCheck.Code.STOCK_DEPOT)
				return false
			if building is Workplace and building.improvement != null:
				removed_improvements.append(building)
			else:
				removed.append(building)
		else:
			placements.append(command)
	var quotes: Dictionary = {}
	var funding: Dictionary = {}
	var cells: Array[Vector2i] = []
	for building in removed: cells.append_array(building.footprint())
	var occupied: Dictionary[Vector2i, bool] = {}
	var terrain: Dictionary[Vector2i, bool] = {}
	var candidates: Array[Building] = []
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
	if last_result.allowed():
		quotes = _quote_orders(commands)
		funding = _funding(quotes, removed)
		last_result = PlacementCheck.result(funding.code)
	if last_result.allowed() and not _safety().preserves_escape(placements, candidates, removed):
		last_result = PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
	if not last_result.allowed():
		for candidate in candidates: candidate.free()
		return false
	# No awaits or notifications until the world and inventory agree.
	_committing = true
	inventory.begin_update()
	var allocations: Dictionary = funding.crates
	var queued_candidates: Array[Building] = []
	if construction == null:
		inventory.try_spend_all(funding.costs, true, true)
	else:
		for crates: Dictionary in allocations.values():
			inventory.debit_build_materials(crates, logistics.main_nest)
		for command in placements:
			if not allocations.has(command):
				inventory.try_spend_all(quotes[command], true, true)
	for command in placements:
		var cell: Vector2i = command.cell
		var option: BuildOption = command.option
		if option is TileBuildOption and not allocations.has(command):
			apply_surface(option, cell)
	for workplace in removed_improvements:
		var definition: WorkplaceUpgradeOption = workplace.improvement
		workplace.remove_improvement()
		_refund_for_demolish(definition)
		if prices != null: prices.record(GameEvents.Kind.BUILDING_DEMOLISHED, definition.id)
	for command in placements:
		if command.option is WorkplaceUpgradeOption and not allocations.has(command):
			var workplace := registry.at(command.cell) as Workplace
			workplace.install_improvement(command.option)
	for building in removed:
		if building is ConstructionSite:
			_remove_site(building)
			continue
		if construction != null:
			var pending: ConstructionSite = construction.at(building.cell)
			if pending != null: _remove_site(pending)
		_refund_for_demolish(building.option)
		building.demolish()
		if prices != null: prices.record(GameEvents.Kind.BUILDING_DEMOLISHED, building.option.id if building.option != null else &"initial")
		building.free()
	var candidate_index := 0
	for command in placements:
		var candidate: Building
		if command.option is SceneBuildOption:
			candidate = candidates[candidate_index]
			candidate_index += 1
		if allocations.has(command):
			construction.enqueue(command, candidate, quotes[command], allocations[command])
			if candidate != null: queued_candidates.append(candidate)
	for candidate in queued_candidates: candidates.erase(candidate)
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
		if allocations.has(command): continue
		if prices != null: prices.record(GameEvents.Kind.TERRAIN_CHANGED if command.option is TileBuildOption else GameEvents.Kind.BUILDING_BUILT, command.option.id)
		built.emit(command.option, command.cell)
	if not removed_improvements.is_empty() or placements.any(func(command: BuildCommand) -> bool: return command.option is WorkplaceUpgradeOption):
		population.planner._queue_workplace_refresh()
	changed.emit()
	return true

func finish_construction(site: ConstructionSite) -> bool:
	return construction.complete(site)

func _remove_site(site: ConstructionSite) -> void:
	construction.cancel(site)
	site.demolish()
	site.queue_free()

## Share of the build cost returned on demolition. 0 = no refund; raise to enable refunds.
const DEMOLISH_REFUND_RATIO := 0.0

func demolition_target(cell: Vector2i) -> Building:
	if construction != null:
		var site: ConstructionSite = construction.at(cell)
		if site == null: site = construction.at(cell, true)
		if site != null: return site
	return registry.at(cell)

func demolition_check(cell: Vector2i) -> PlacementCheck:
	if _committing:
		return PlacementCheck.result(PlacementCheck.Code.BUSY)
	var building: Building = demolition_target(cell)
	if construction != null and (construction.at(cell) != null or construction.at(cell, true) != null): return PlacementCheck.new()
	if building is House and logistics != null and not logistics.can_remove(building):
		return PlacementCheck.result(PlacementCheck.Code.STOCK_DEPOT)
	if not _safety().can_remove_food(building):
		return PlacementCheck.result(PlacementCheck.Code.NO_ESCAPE)
	return PlacementCheck.result(PlacementCheck.Code.OK if building != null else PlacementCheck.Code.NO_BUILDING)

## Demolishes the building on the cell. No confirmation; residents die with DEMOLISHED.
## The presentation requests confirmation; this command has no UI dependencies.
func demolish_at(cell: Vector2i) -> bool:
	last_result = demolition_check(cell)
	if not last_result.allowed():
		return false
	var building: Building = registry.at(cell)
	if construction != null:
		var site: ConstructionSite = construction.at(cell)
		if site == null: site = construction.at(cell, true)
		if site != null:
			_remove_site(site)
			changed.emit()
			return true
	_committing = true
	inventory.begin_update()
	if building is Workplace and building.improvement != null:
		var definition: WorkplaceUpgradeOption = building.improvement
		building.remove_improvement()
		_refund_for_demolish(definition)
		if prices != null: prices.record(GameEvents.Kind.BUILDING_DEMOLISHED, definition.id)
		_committing = false
		inventory.end_update()
		population.planner._queue_workplace_refresh()
		changed.emit()
		return true
	_refund_for_demolish(building.option)
	var changed_cells: Array[Vector2i] = building.footprint()
	building.demolish()
	if prices != null: prices.record(GameEvents.Kind.BUILDING_DEMOLISHED, building.option.id if building.option != null else &"initial")
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

func _safety() -> ConstructionSafety:
	return ConstructionSafety.new(map, registry, population, route_service)

func price(option: BuildOption, cell := Vector2i(2147483647, 2147483647)) -> Array[ResourceAmount]:
	var factor: float = terrain.price_multiplier(option, cell) if terrain != null else 1.0
	return prices.quote(option, {}, factor) if prices != null else option.costs

func apply_surface(option: TileBuildOption, cell: Vector2i) -> void:
	if map is TerrainMap:
		map.paint_tile(cell, Vector4i(option.source_id, option.atlas_coords.x, option.atlas_coords.y, option.alternative_tile))
	else: map.set_cell(cell, option.source_id, option.atlas_coords, option.alternative_tile)

static func price_amount(costs: Array[ResourceAmount], type: ResourceType) -> int:
	var result := 0
	for entry in costs:
		if entry != null and entry.type != null and type != null and entry.type.id == type.id: result += entry.amount
	return result

func _base_plan_price(commands: Array[BuildCommand]) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	for command in commands:
		if not command.is_removal(): result.append_array(price(command.option, command.cell))
	return result
