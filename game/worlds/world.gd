extends Node2D
class_name World
## Composition root. Owns services and lifecycle, never shell navigation or input.

@export var art: ArtCatalog
@export var auto_start := true
@export var map: TileMapLayer
@export var starting_resources: Array[ResourceAmount] = []
@export var task_deck: TaskDeck
@export var voyage_rules: VoyageRules
@export var satiety_rules: SatietyRules
@export var island_generation: IslandGenerationRules
@export var chapter_rules: FirstChapterRules
@export var queen: QueenActor
@export var chapter_spawn_points: Array[Marker2D] = []
var chapter: Node
var map_size: Vector2i:
	get:
		return map.get_used_rect().size
@export var diagnostics_enabled := false
var endless := false
var voyage: Voyage
@export var waves: CombatDirector
var combat: CombatDirector
var tasks: TaskDirector
var opening_order: TaskSpec
@export var prices: PriceService
var terrain: TerrainRules
@export var construction_service: ConstructionService
@export var terrain_rules: TerrainRules
@export var inventory: WorldInventory
@export var logistics: ColonyLogistics
@export var build_controller: BuildController
@export var route_service: RouteService
@export var registry: BuildingRegistry
@export var population: ColonyPopulation
@export var planner: TripPlanner
@export var match_controller: MatchController
@export var units: Node2D
@export var buildings: Node2D
var ready_for_play := false
var _navigation_update_queued := false

func _ready() -> void:
	if waves.enabled:
		var errors: Array[String] = waves.validate()
		if not errors.is_empty():
			for error in errors:
				push_error(error)
			return
	else:
		waves.process_mode = Node.PROCESS_MODE_DISABLED
	var build_options: Array[BuildOption] = build_controller.initial_options()
	if waves.enabled:
		build_options.append_array(waves.rules.defenses.options)
	if art == null or not art.validate().is_empty():
		push_error("Invalid world art catalog")
		return
	if satiety_rules == null or not satiety_rules.is_valid():
		push_error("World requires valid satiety rules")
		return
	if map.tile_set == null or map.get_used_cells().is_empty():
		push_error("World requires a painted TileMapLayer with a TileSet")
		return
	if not inventory.configure(starting_resources):
		return
	route_service.setup(map)
	route_service.rebuild()
	registry.added.connect(_configure_building)
	registry.changed.connect(_queue_navigation_update)
	if map is TerrainMap:
		terrain = terrain_rules
		terrain.configure(map, registry)
		prices.configure_terrain(terrain.price_multiplier)
	logistics.configure(inventory, route_service, registry)
	planner.configure(registry, route_service, inventory, inventory.type_by_id(&"food"), logistics, satiety_rules)
	population.configure(units, route_service, planner, registry, logistics)
	build_controller.prices = prices
	build_controller.route_service = route_service
	build_controller.configure(map, buildings, inventory, build_options)
	build_controller.registry = registry
	build_controller.population = population
	build_controller.logistics = logistics
	build_controller.terrain = terrain
	if terrain != null: terrain.changed.connect(func(): population.changed.emit())
	if build_controller.physical_construction:
		var construction := construction_service
		construction.configure(build_controller, art)
		build_controller.construction = construction
		logistics.construction = construction
		population.construction = construction
	build_controller.changed.connect(func(): _navigation_update_queued = false)
	_register_initial_buildings()
	_prepare_initial_routes()
	if task_deck != null:
		var errors: Array[String] = task_deck.validate(inventory)
		if not errors.is_empty():
			for error in errors: push_error(error)
			return
		match_controller.task_mode = true
		tasks = TaskDirector.new()
		tasks.configure(self, task_deck, randi(), opening_order)
		match_controller.completed.connect(func(summary: MatchSummary):
			summary.development_level = tasks.level
			summary.tasks_completed = tasks.completed_count
			summary.tasks_skipped = tasks.skipped_count)
	if waves.enabled:
		combat = waves
		combat.configure(self, waves.rules)
	if not endless and tasks != null and voyage_rules != null:
		voyage = Voyage.new()
		voyage.configure(self, voyage_rules)
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

func _register_initial_buildings() -> void:
	# All setup() calls must finish before navigation is generated,
	# otherwise units spawned by houses would appear before the grid exists.
	# A base snapshot already exists; registry commits then apply blocking footprints.
	var initial: Array[Building] = placed_buildings()
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

func _prepare_initial_routes() -> void:
	route_service.rebuild(registry.blocked_cells())
	planner.refresh_food()
	route_service.food_field()
	planner.prepare_workplaces()
	for building in registry.all():
		if building is House:
			planner.prepare_home(building)
	for ant in population.agents():
		ant.refresh_meal_reservation()

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
		node.supply_changed.connect(planner.queue_workplace_refresh)

func _configure_building(building: Building) -> void:
	if building is Workplace: building.inventory = inventory
	_subscribe_workplace(building)
	building.configure_appearance(art, route_service.cell_size())

func _on_workplace_produced(type: ResourceType, amount: int) -> void:
	prices.record(GameEvents.Kind.RESOURCE_PRODUCED, type.id, amount)

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

func placed_buildings() -> Array[Building]:
	var found: Array[Building] = []
	_collect_buildings(self, found)
	return found

func _collect_buildings(root: Node, found: Array[Building]) -> void:
	for child in root.get_children():
		if child is Building:
			found.append(child)
		else:
			_collect_buildings(child, found)

func map_bounds() -> Rect2:
	var region: Rect2i = map.get_used_rect()
	return map.transform * Rect2(Vector2(region.position * map.tile_set.tile_size), Vector2(region.size * map.tile_set.tile_size))
