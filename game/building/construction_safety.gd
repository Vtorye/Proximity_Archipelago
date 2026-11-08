class_name ConstructionSafety
extends RefCounted
## Pure preflight against the final grid; never mutates stock, buildings, or navigation.
var map: TileMapLayer
var registry: BuildingRegistry
var population: ColonyPopulation
var route_service: RouteService
func _init(tile_map: TileMapLayer, buildings: BuildingRegistry, ants: ColonyPopulation, routes: RouteService) -> void:
	map = tile_map
	registry = buildings
	population = ants
	route_service = routes

func preserves_escape(commands: Array[BuildCommand], candidates: Array[Building], removed: Array[Building] = []) -> bool:
	var values: Dictionary[Vector2i, float] = {}
	var needs_check := not removed.is_empty()
	for building in removed:
		for cell in building.footprint():
			var data: TileData = map.get_cell_tile_data(cell)
			values[cell] = float(data.get_custom_data("move_cost")) if data != null else 0.0
	needs_check = needs_check or not candidates.is_empty()
	for command in commands:
		var cell: Vector2i = command.cell
		var option: BuildOption = command.option
		if option is TileBuildOption:
			var source: TileSetAtlasSource = map.tile_set.get_source(option.source_id) as TileSetAtlasSource
			var key := Vector4i(option.source_id, option.atlas_coords.x, option.atlas_coords.y, option.alternative_tile)
			var next_type: TerrainType = map.catalog.for_tile(map.result_key(cell, key)) if map is TerrainMap else null
			var value: float = next_type.move_cost if next_type != null else float(source.get_tile_data(option.atlas_coords, option.alternative_tile).get_custom_data("move_cost"))
			values[cell] = value
			needs_check = needs_check or value <= 0.0 or value > route_service.entry_cost(cell)
	for candidate in candidates:
		if candidate.option.blocks_movement:
			for target in candidate.footprint(): values[target] = 0.0
	if not needs_check:
		return true
	var grid: TileGrid = route_service.snapshot()
	var preview: TileGrid = grid.with_costs(values) if not values.is_empty() else grid
	for candidate in candidates:
		if not candidate.entry_cells().any(preview.walkable):
			return false
	if values.is_empty():
		return true
	var foods: Array[Vector2i] = []
	for canteen in registry.canteens():
		if not removed.has(canteen): foods.append_array(canteen.entry_cells())
	for candidate in candidates:
		if candidate is Canteen: foods.append_array(candidate.entry_cells())
	return _agents_can_escape(preview, GridSearch.build(preview, foods, true), removed)

func _agents_can_escape(grid: TileGrid, field: NavigationField, removed: Array[Building] = []) -> bool:
	var previous: NavigationField = route_service.food_field()
	for ant in population.agents():
		if removed.has(ant.home): continue
		var cell: Vector2i = route_service.world_to_cell(ant.global_position)
		if not grid.walkable(cell):
			return false
		var speed: float = ant.speed * TripPlanner.CARRY_SPEED_RATIO
		var before: float = previous.cost(cell) * route_service.cell_size() / speed + AntNeeds.MEAL_SECONDS
		var after: float = field.cost(cell) * route_service.cell_size() / speed + AntNeeds.MEAL_SECONDS
		if ant.needs.can_afford(before) and not ant.needs.can_afford(after):
			return false
	return true

func can_remove_food(building: Building) -> bool:
	if not building is Canteen:
		return true
	var remaining: Array[Vector2i] = []
	for canteen in registry.canteens():
		if canteen != building:
			remaining.append_array(canteen.entry_cells())
	var grid: TileGrid = route_service.snapshot()
	return _agents_can_escape(grid, GridSearch.build(grid, remaining, true))

