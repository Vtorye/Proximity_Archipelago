extends Node2D
class_name World
## Composition root. Owns services and lifecycle, never shell navigation or input.

@export var starting_resources: Array[ResourceAmount] = []
@export var build_catalog: BuildCatalog
@export var build_options: Array[BuildOption] = []
@export var art: ArtCatalog = preload("res://game/art/colony_art.tres")
@export var auto_start := true
@export var ant_construction := true
@export var recruitment: RecruitmentCatalog = preload("res://game/resources/recruitment.tres")
var map_size: Vector2i:
	get: return ($Map as TileMapLayer).get_used_rect().size
@export var diagnostics_enabled := false
@export var wave_rules: WaveRules
@export var worker_scene: PackedScene = preload("res://game/ants/worker.tscn")
@export var carrier_scene: PackedScene = preload("res://game/ants/carrier.tscn")
@export var warrior_scene: PackedScene = preload("res://game/ants/warrior.tscn")
var voyage: Voyage
var combat: CombatDirector
@export var task_deck: TaskDeck
var tasks: TaskDirector
var events: WorldEvents
var prices: PriceService
var terrain: TerrainRules
var inventory: WorldInventory
var logistics: ColonyLogistics
var build_controller: BuildController
var route_service: RouteService
var registry: BuildingRegistry
var population: ColonyPopulation
var planner: TripPlanner
var match_controller: MatchController
var units: Node2D
var buildings: Node2D
var ready_for_play := false
var _navigation_update_queued := false

func _ready() -> void:
	if wave_rules != null and not wave_rules.validate().is_empty():
		for error in wave_rules.validate(): push_error(error)
		return
	if build_catalog != null: build_options = build_catalog.options.duplicate()
	if wave_rules != null and wave_rules.defenses != null: build_options.append_array(wave_rules.defenses.options)
	prices = PriceService.new()
	events = prices.events
	prices.definitions = build_options
	prices.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(prices)
	var map: TileMapLayer = $Map
	if not art.validate().is_empty():
		push_error("Invalid world art catalog")
		return
	if map.tile_set == null or map.get_used_cells().is_empty():
		push_error("World requires a painted TileMapLayer with a TileSet")
		return
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
	if map is TerrainMap:
		terrain = TerrainRules.new()
		terrain.name = "TerrainRules"
		add_child(terrain)
		terrain.configure(map, registry)
		prices.terrain_multiplier = terrain.price_multiplier
	logistics = ColonyLogistics.new()
	logistics.name = "Logistics"
	add_child(logistics)
	logistics.configure(inventory, route_service, registry)
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
	population.configure(units, route_service, planner, registry, logistics)
	population.recruitment = recruitment
	population.worker_scene = worker_scene
	population.carrier_scene = carrier_scene
	population.warrior_scene = warrior_scene
	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	build_controller.prices = prices
	build_controller.route_service = route_service
	add_child(build_controller)
	build_controller.configure(map, buildings, inventory, build_options)
	build_controller.registry = registry
	build_controller.population = population
	build_controller.logistics = logistics
	build_controller.terrain = terrain
	if terrain != null: terrain.changed.connect(func(): population.changed.emit())
	if ant_construction:
		var construction := ConstructionService.new()
		construction.name = "Construction"
		construction.controller = build_controller
		construction.art = art
		build_controller.construction = construction
		add_child(construction)
		construction.changed.connect(planner._queue_workplace_refresh)
		population.construction = construction
	build_controller.changed.connect(func(): _navigation_update_queued = false)
	# All setup() calls must finish before navigation is generated,
	# otherwise units spawned by houses would appear before the grid exists.
	# A base snapshot already exists; registry commits then apply blocking footprints.
	var initial: Array[Building] = []
	_collect_buildings(self, initial)
	# Authored bases must register before barracks, regardless of scene tree order.
	var bases: Array[Building] = []
	var others: Array[Building] = []
	for building in initial:
		if building is House and building.is_main_nest:
			bases.append(building)
		else:
			others.append(building)
	initial = bases + others
	for building in initial:
		if not building.has_meta(&"layout_kind"): building.set_meta(&"layout_kind", str(get_path_to(building)))
		var origin: Vector2i = map.local_to_map(map.to_local(building.global_position))
		if building.setup(origin, building.option):
			registry.register(building)
	route_service.rebuild(registry.blocked_cells())
	planner.refresh_food()
	route_service.food_field()
	planner.prepare_workplaces()
	for building in registry.all():
		if building is House:
			planner.prepare_home(building)
	for ant in population.agents():
		ant.refresh_meal_reservation()
	match_controller = get_node_or_null("MatchController") as MatchController
	if task_deck != null:
		var errors: Array[String] = task_deck.validate(inventory)
		if not errors.is_empty():
			for error in errors: push_error(error)
			return
		match_controller.task_mode = true
		tasks = TaskDirector.new()
		tasks.configure(self, task_deck, randi())
		match_controller.completed.connect(func(summary: MatchSummary):
			summary.development_level = tasks.level
			summary.tasks_completed = tasks.completed_count
			summary.tasks_skipped = tasks.skipped_count)
	if wave_rules != null:
		combat = CombatDirector.new()
		combat.name = "Combat"
		combat.z_index = 3
		add_child(combat)
		combat.configure(self, wave_rules)
	if tasks != null:
		voyage = Voyage.new()
		voyage.configure(self)
	ready_for_play = true
	if diagnostics_enabled:
		var observer := DebugProbe.new()
		observer.enabled = true
		observer.configure(self)
		add_child(observer)
	if auto_start:
		start()
	else:
		process_mode = Node.PROCESS_MODE_DISABLED

func start() -> void:
	if not ready_for_play:
		return
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if match_controller != null:
		match_controller.start(inventory)

func stop() -> void:
	if match_controller != null:
		match_controller.stop()
	process_mode = Node.PROCESS_MODE_DISABLED

## Publishes production events when work completes. Safe to call more than once.
func _subscribe_workplace(node: Node) -> void:
	if node is Workplace and not node.produced.is_connected(_on_workplace_produced):
		node.produced.connect(_on_workplace_produced)
		node.supply_changed.connect(planner._queue_workplace_refresh)

func _configure_building(building: Building) -> void:
	if building is Workplace: building.inventory = inventory
	_subscribe_workplace(building)
	var sprite: Sprite2D = building.get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		if building.option != null and building.option.icon != null:
			sprite.texture = building.option.icon
		elif building is House:
			sprite.texture = art.nest
		elif building is Canteen:
			sprite.texture = art.canteen
			sprite.modulate = Color.WHITE
		elif building is Workplace:
			var product: ResourceType = building.output
			if product == null and building.recipe != null and not building.recipe.outputs.is_empty(): product = building.recipe.outputs[0].type
			if product != null and product.icon != null: sprite.texture = product.icon
			elif sprite.texture == null:
				var resource_id: StringName = product.id if product != null else &""
				sprite.texture = art.berries if resource_id == &"food" else (art.timber if resource_id == &"wood" else art.stone)
		if sprite.texture != null:
			if building is Workplace:
				building.refresh_appearance(sprite.texture)
			sprite.scale = Vector2.ONE * route_service.cell_size() / sprite.texture.get_width()

func _on_workplace_produced(type: ResourceType, amount: int) -> void:
	events.publish(GameEvents.Kind.RESOURCE_PRODUCED, type.id, amount)

func _queue_navigation_update() -> void:
	if ready_for_play and not _navigation_update_queued:
		_navigation_update_queued = true
		_update_navigation.call_deferred()

func _update_navigation() -> void:
	if not _navigation_update_queued:
		return
	_navigation_update_queued = false
	if is_inside_tree():
		route_service.rebuild(registry.blocked_cells())

func _collect_buildings(root: Node, found: Array[Building]) -> void:
	for child in root.get_children():
		if child is Building:
			found.append(child)
		else:
			_collect_buildings(child, found)

func map_bounds() -> Rect2:
	var map: TileMapLayer = $Map
	var region: Rect2i = map.get_used_rect()
	return map.transform * Rect2(Vector2(region.position * map.tile_set.tile_size), Vector2(region.size * map.tile_set.tile_size))
