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

func can_remove_food(building: Building) -> bool:
	if not building is Canteen:
		return true
	var remaining: Array[Vector2i] = []
	for canteen in registry.canteens():
		if canteen != building:
			remaining.append_array(canteen.entry_cells())
	return _agents_can_escape(GridSearch.build(route_service.snapshot(), remaining, true))

