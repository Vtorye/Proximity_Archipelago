class_name ConstructionSafety
extends RefCounted
## Projects the final grid and finds safe exits for ants on cells it closes.
var map: TileMapLayer
var registry: BuildingRegistry
var population: ColonyPopulation
var route_service: RouteService
var exits: Dictionary[AntAgent, Vector2i] = {}

func _init(tile_map: TileMapLayer, buildings: BuildingRegistry, ants: ColonyPopulation, routes: RouteService) -> void:
	map = tile_map
	registry = buildings
	population = ants
	route_service = routes

func check(commands: Array[BuildCommand], candidates: Array[Building], removed: Array[Building] = []) -> PlacementCheck.Code:
	exits.clear()
	var grid := route_service.snapshot()
	var values: Dictionary[Vector2i, float] = {}
	var needs_escape_check := false
	for building in removed:
		if building is Canteen:
			needs_escape_check = true
		if not building is ConstructionSite and building.option is SceneBuildOption and building.option.blocks_movement:
			for cell in building.footprint():
				values[cell] = TileGrid.terrain_cost_at(map, cell)
	for command in commands:
		if command.option is TileBuildOption:
			var cell := command.cell
			var option := command.option as TileBuildOption
			var source := map.tile_set.get_source(option.source_id) as TileSetAtlasSource
			var key := Vector4i(option.source_id, option.atlas_coords.x, option.atlas_coords.y, option.alternative_tile)
			var next_type: TerrainType = map.catalog.for_tile(map.result_key(cell, key)) if map is TerrainMap else null
			var value: float = next_type.move_cost if next_type != null else float(source.get_tile_data(option.atlas_coords, option.alternative_tile).get_custom_data("move_cost"))
			values[cell] = value
			needs_escape_check = needs_escape_check or (grid.walkable(cell) and (value <= 0.0 or value > grid.cost(cell)))
	for candidate in candidates:
		if candidate.option.blocks_movement:
			for cell in candidate.footprint():
				values[cell] = 0.0
				needs_escape_check = needs_escape_check or grid.walkable(cell)
	var preview := grid.with_costs(values) if not values.is_empty() else grid
	for candidate in candidates:
		if not candidate.entry_cells().any(preview.walkable):
			return PlacementCheck.Code.NO_ENTRANCE
	if not needs_escape_check:
		return PlacementCheck.Code.OK
	var foods := _food_entries(removed)
	for candidate in candidates:
		if candidate is Canteen:
			foods.append_array(candidate.entry_cells())
	if not _agents_can_escape(grid, preview, GridSearch.build(preview, foods, true), removed):
		return PlacementCheck.Code.NO_ESCAPE
	return PlacementCheck.Code.OK

func _food_entries(removed: Array[Building]) -> Array[Vector2i]:
	var foods: Array[Vector2i] = []
	for canteen in registry.canteens():
		if not removed.has(canteen):
			foods.append_array(canteen.entry_cells())
	return foods

func _agents_can_escape(grid: TileGrid, preview: TileGrid, field: NavigationField, removed: Array[Building]) -> bool:
	var previous := route_service.food_field()
	var egress_fields: Dictionary[Vector2i, NavigationField] = {}
	for ant in population.agents():
		if removed.has(ant.home): continue
		var cell := route_service.world_to_cell(ant.global_position)
		if not grid.walkable(cell): continue
		var had_safe_route := _can_afford_route(ant, previous.cost(cell))
		if preview.walkable(cell):
			if had_safe_route and not _can_afford_route(ant, field.cost(cell)):
				return false
			continue
		var exit := _find_exit(ant, cell, grid, preview, field, had_safe_route, egress_fields)
		if not preview.walkable(exit):
			return false
		exits[ant] = exit
	return true

func _can_afford_route(ant: AntAgent, cost: float) -> bool:
	var energy := ant.planner.travel_energy(cost, ant.movement_speed())
	return ant.needs.can_afford(energy + AntNeeds.MEAL_SECONDS * AntNeeds.EAT_RATE)

func _find_exit(ant: AntAgent, start: Vector2i, grid: TileGrid, preview: TileGrid,
		food: NavigationField, needs_food_route: bool, fields: Dictionary[Vector2i, NavigationField]) -> Vector2i:
	# Only consider the boundary of the connected cells that this build covers.
	# An ant can leave that area before it closes, using cells it could already enter.
	var covered: Array[Vector2i] = [start]
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var boundary: Array[Vector2i] = []
	var index := 0
	while index < covered.size():
		for neighbor in grid.neighbors(covered[index]):
			if seen.has(neighbor): continue
			seen[neighbor] = true
			if preview.walkable(neighbor):
				boundary.append(neighbor)
			else:
				covered.append(neighbor)
		index += 1
	var best := start
	var best_cost := INF
	if boundary.is_empty(): return best
	if covered.size() > 1 and not fields.has(start):
		fields[start] = GridSearch.build(grid, [start])
	for exit in boundary:
		var travel: float = grid.cost(exit) if covered.size() == 1 else fields[start].cost(exit)
		var cost: float = travel + food.cost(exit) if needs_food_route else travel
		if cost < best_cost and (not needs_food_route or _can_afford_route(ant, cost)):
			best = exit
			best_cost = cost
	return best

func can_remove_food(building: Building) -> bool:
	if not building is Canteen:
		return true
	var grid := route_service.snapshot()
	return _agents_can_escape(grid, grid, GridSearch.build(grid, _food_entries([building]), true), [])
