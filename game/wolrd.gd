extends Node2D
class_name World
## Composition root. Owns services and lifecycle, never shell navigation or input.

const CELL_SIZE := 16
@export var starting_resources: Array[ResourceAmount] = []
@export var build_options: Array[BuildOption] = []
@export var art: ArtCatalog = preload("res://game/art/colony_art.tres")
@export var auto_start := true
@export var map_size := Vector2i(100, 100)
@export var generate_archipelago := true
var inventory: WorldInventory
var build_controller: BuildController
var route_service: RouteService
var registry: BuildingRegistry
var population: ColonyPopulation
var planner: TripPlanner
var match_controller: MatchController
var units: Node2D
var buildings: Node2D
var ready_for_play := false

func _ready() -> void:
	var map: TileMapLayer = $Map
	if not art.validate().is_empty():
		push_error("Invalid world art catalog")
		return
	_configure_terrain(map)
	if generate_archipelago:
		_generate_terrain(map)
	inventory = WorldInventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	if not inventory.configure(starting_resources):
		return
	route_service = RouteService.new()
	route_service.name = "RouteService"
	add_child(route_service)
	route_service.setup(map)
	route_service.rebuild()
	registry = BuildingRegistry.new()
	registry.name = "BuildingRegistry"
	add_child(registry)
	registry.added.connect(_configure_building)
	registry.changed.connect(_queue_navigation_update)
	planner = TripPlanner.new()
	planner.name = "TripPlanner"
	add_child(planner)
	planner.configure(registry, route_service, inventory, inventory.type_by_id(&"food"))
	units = Node2D.new()
	units.name = "Units"
	units.z_index = 2
	add_child(units)
	buildings = Node2D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	population = ColonyPopulation.new()
	population.name = "Population"
	add_child(population)
	population.configure(units, route_service, planner, registry)
	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	build_controller.route_service = route_service
	add_child(build_controller)
	build_controller.configure(map, buildings, inventory, build_options)
	build_controller.registry = registry
	build_controller.population = population
	# All setup() calls must finish before navigation is generated,
	# otherwise units spawned by houses would appear before the grid exists.
	# A base snapshot already exists; registry commits then apply blocking footprints.
	for child in get_children():
		if child is Building:
			var building: Building = child as Building
			var origin: Vector2i = map.local_to_map(map.to_local(building.global_position))
			if building.setup(origin, building.option):
				registry.register(building)
	route_service.rebuild(registry.blocked_cells())
	planner.refresh_food()
	match_controller = get_node_or_null("MatchController") as MatchController
	ready_for_play = true
	if auto_start:
		start()
	else:
		process_mode = Node.PROCESS_MODE_DISABLED

func start() -> void:
	if not ready_for_play:
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	if match_controller != null:
		match_controller.start(inventory)

func stop() -> void:
	if match_controller != null:
		match_controller.stop()
	process_mode = Node.PROCESS_MODE_DISABLED

## Connects a workplace's output to the world inventory. Safe to call more than once.
func _subscribe_workplace(node: Node) -> void:
	if node is Workplace and not node.produced.is_connected(_on_workplace_produced):
		node.produced.connect(_on_workplace_produced)

func _configure_building(building: Building) -> void:
	_subscribe_workplace(building)
	if building is Canteen:
		building.configure(inventory, inventory.type_by_id(&"food"))
	var sprite: Sprite2D = building.get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		if building is House or building is Canteen:
			sprite.texture = art.nest
		elif building is Workplace:
			var resource_id: StringName = building.output.id if building.output != null else &""
			sprite.texture = art.berries if resource_id == &"food" else (art.timber if resource_id == &"wood" else art.stone)
		if sprite.texture != null:
			sprite.scale = Vector2.ONE * CELL_SIZE / sprite.texture.get_width()

func _on_workplace_produced(type: ResourceType, amount: int) -> void:
	if not inventory.add(type, amount):
		push_warning("World could not store %d of %s" % [amount, type.id])

func _configure_terrain(map: TileMapLayer) -> void:
	var pixels: int = art.tile_resolution()
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(pixels, pixels)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "move_cost")
	tiles.set_custom_data_layer_type(0, TYPE_FLOAT)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = art.terrain_atlas()
	atlas.texture_region_size = Vector2i(pixels, pixels)
	tiles.add_source(atlas, 3)
	for index in range(4):
		atlas.create_tile(Vector2i(index, 0))
		atlas.get_tile_data(Vector2i(index, 0), 0).set_custom_data("move_cost", [1.0, 1.6, 0.6, 0.0][index])
	map.tile_set = tiles
	map.scale = Vector2.ONE * CELL_SIZE / pixels

func _queue_navigation_update() -> void:
	if ready_for_play:
		_update_navigation.call_deferred()

func _update_navigation() -> void:
	if is_inside_tree():
		route_service.rebuild(registry.blocked_cells())

func _generate_terrain(map: TileMapLayer) -> void:
	map.clear()
	var noise := FastNoiseLite.new()
	noise.seed = 1147
	noise.frequency = 0.16
	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			var main: Vector2 = (Vector2(cell) - Vector2(50, 50)) / Vector2(33, 25)
			var west: Vector2 = (Vector2(cell) - Vector2(18, 20)) / Vector2(13, 10)
			var east: Vector2 = (Vector2(cell) - Vector2(81, 77)) / Vector2(13, 12)
			var shape: float = minf(main.length_squared(), minf(west.length_squared(), east.length_squared()))
			var edge: float = 1.0 + noise.get_noise_2d(x, y) * 0.18
			var terrain := 3
			if shape < edge:
				terrain = 1 if shape > edge - 0.12 else 0
			if x >= 46 and x <= 55 and y == 50 or x == 50 and y >= 46 and y <= 54:
				terrain = 2
			map.set_cell(cell, 3, Vector2i(terrain, 0))
