extends Node
## Executable regressions: a failure changes the process exit code.
const WORLD := preload("res://game/worlds/wolrd_1.tscn")
const ASTAR := preload("res://game/navigation/astar_path_finder.gd")
const DIJKSTRA := preload("res://game/navigation/dijkstra_path_finder.gd")
var failures: Array[String] = []
var assertions := 0
var metrics := {}

func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		print("FAIL ", message)

func entry(type: ResourceType, count: int) -> ResourceAmount:
	var result := ResourceAmount.new()
	result.type = type
	result.amount = count
	return result

func resource(id: StringName) -> ResourceType:
	var type := ResourceType.new()
	type.id = id
	type.display_name = String(id)
	return type

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261025)
	_test_manifest()
	_test_stock()
	_test_navigation()
	_test_resident_pruning()
	await _test_worlds()
	await _test_assignment_load()
	await _test_rules()
	await _test_art_resolution()
	await _test_simulation()
	print("TEST REPORT ", JSON.stringify({"assertions": assertions, "failures": failures, "metrics": metrics}))
	print("TESTS PASS" if failures.is_empty() else "TESTS FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_manifest() -> void:
	var manifest: Manifest = load("res://manifest.tres") as Manifest
	expect(manifest.validate().is_empty(), "registered screens and overlays have valid roots")
	var invalid: Manifest = manifest.duplicate() as Manifest
	invalid.screens = manifest.screens.duplicate()
	var node := Node.new()
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	invalid.screens[&"invalid"] = packed
	expect(not invalid.validate().is_empty(), "manifest catches invalid screen roots before boot")

func _test_stock() -> void:
	var food: ResourceType = resource(&"food")
	var stock := WorldInventory.new()
	expect(stock.configure([entry(food, 1)]), "stock config")
	var ticket: StockReservation = stock.reserve(food)
	expect(ticket != null and stock.quantity(food) == 1 and stock.available(food) == 0, "reserved food stays in total stock")
	expect(stock.reserve(food) == null, "last meal cannot be reserved twice")
	expect(not stock.try_spend(entry(food, 1)), "construction cannot spend reserved food")
	expect(stock.consume(ticket), "reserved meal consumed")
	expect(not stock.consume(ticket) and stock.quantity(food) == 0, "meal consumed once")
	stock.add(food, 5)
	var held: StockReservation = stock.reserve(food)
	stock.configure([entry(food, 5)])
	expect(not held.active and stock.available(food) == 5, "reconfigure clears food claims")
	var notifications: Array[int] = [0]
	stock.changed.connect(func(): notifications[0] += 1)
	stock.begin_update()
	stock.add(food, 2)
	stock.try_spend(entry(food, 1))
	expect(notifications[0] == 0, "no intermediate inventory notification")
	stock.end_update()
	expect(notifications[0] == 1, "one committed inventory notification")
	stock.free()

func _test_navigation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025
	for sample in range(15):
		var grid := TileGrid.new()
		var costs := PackedFloat32Array()
		for index in range(81):
			costs.append(0.0 if rng.randf() < 0.2 else [0.5, 1.0, 2.0][rng.randi_range(0, 2)])
		grid.configure(Rect2i(-2, -3, 9, 9), costs)
		var astar: PathAlgorithm = ASTAR.new()
		var dijkstra: PathAlgorithm = DIJKSTRA.new()
		astar.build(grid)
		dijkstra.build(grid)
		for query in range(12):
			var start := Vector2i(rng.randi_range(-2, 6), rng.randi_range(-3, 5))
			var finish := Vector2i(rng.randi_range(-2, 6), rng.randi_range(-3, 5))
			var expected: float = _reference(grid, start, finish)
			for algorithm in [astar, dijkstra]:
				var actual: float = algorithm.get_cost(start, finish)
				expect((is_inf(actual) and is_inf(expected)) or is_equal_approx(actual, expected), "path cost matches independent reference")
	var grid := TileGrid.new()
	grid.configure(Rect2i(0, 0, 3, 1), PackedFloat32Array([1.0, 2.0, 3.0]))
	var reverse: NavigationField = GridSearch.build(grid, [Vector2i(2, 0)], true)
	expect(is_equal_approx(reverse.cost(Vector2i.ZERO), 5.0), "reverse field preserves destination-entry costs")
	expect(reverse.path(Vector2i.ZERO) == [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)], "reverse field follows a valid goal route")
	var large := TileGrid.new()
	var values := PackedFloat32Array()
	values.resize(10000)
	values.fill(1.0)
	large.configure(Rect2i(0, 0, 100, 100), values)
	var service := RouteService.new()
	service.configure_grid(large)
	var before: int = Time.get_ticks_usec()
	var field: NavigationField = service.distances_from(Vector2i.ZERO)
	var cold_us: int = Time.get_ticks_usec() - before
	before = Time.get_ticks_usec()
	for query in range(10000):
		service.distances_from(Vector2i.ZERO).cost(Vector2i(query % 100, query / 100))
	var hits_us: int = Time.get_ticks_usec() - before
	expect(service.search_count == 1 and service.cache_hits == 10000, "ten thousand destination reads share one search")
	for index in range(12):
		service.distances_from(Vector2i(index, 0))
	expect(service._fields.size() <= RouteService.MAX_CACHED_FIELDS, "navigation cache stays bounded")
	metrics["navigation_100x100"] = {"cold_field_ms": cold_us / 1000.0, "10000_cached_reads_ms": hits_us / 1000.0, "field_bytes": field.costs.size() * 4 + field.parents.size(), "cache_limit": RouteService.MAX_CACHED_FIELDS}
	service.free()

func _reference(grid: TileGrid, start: Vector2i, finish: Vector2i) -> float:
	if not grid.walkable(start) or not grid.walkable(finish):
		return INF
	var distances := {start: 0.0}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for next in grid.neighbors(cell):
			var cost: float = float(distances[cell]) + grid.cost(next)
			if cost < float(distances.get(next, INF)):
				distances[next] = cost
				if not queue.has(next): queue.append(next)
	return float(distances.get(finish, INF))

func _test_resident_pruning() -> void:
	var house := House.new()
	var resident := Node2D.new()
	house.add_resident(resident)
	resident.free()
	expect(house.has_space() and house.residents.is_empty(), "freed resident safely removed")
	var view: Array[Node2D] = house.residents
	view.append(Node2D.new())
	expect(house.residents.is_empty(), "resident snapshot cannot mutate house")
	view[0].free()
	house.free()

func make_world() -> World:
	var world: World = WORLD.instantiate() as World
	world.auto_start = false
	add_child(world)
	return world

func _test_worlds() -> void:
	var first: World = make_world()
	var second: World = make_world()
	expect(first.population.count() == 10 and second.population.count() == 10, "worlds own independent ant populations")
	for ant in second.population.agents():
		expect(ant.get_parent() == second.units and ant.route_service == second.route_service and ant.planner.inventory == second.inventory, "second world has no first-world dependency")
	var house: House = second.get_node("Home") as House
	var origin: Vector2i = house.cell
	house.free()
	expect(second.registry.at(origin) == null and second.population.count() == 5, "external nest removal clears occupancy and residents")
	var food: ResourceType = first.inventory.type_by_id(&"food")
	var wood: ResourceType = first.inventory.type_by_id(&"wood")
	var ant: AntAgent = first.population.agents()[0]
	ant.needs.satiety = 12.0
	var plan: WorkPlan = first.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	expect(plan == null, "unsafe outward-work-return-food assignment rejected")
	ant.needs.eat()
	plan = first.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	expect(plan != null and plan.estimated_energy + AntNeeds.SAFETY_MARGIN <= ant.needs.satiety, "healthy ant receives a complete feasible plan")
	if plan != null: plan.workplace.release_worker(ant)
	var options: Array[BuildOption] = first.build_controller.options
	var nest: SceneBuildOption = load("res://game/building/options/house.tres").duplicate(true) as SceneBuildOption
	nest.blocks_movement = true
	nest.cost = entry(wood, 0)
	options.append(nest)
	var built: bool = first.build_controller.try_build(nest, Vector2i(52, 54))
	expect(built, "blocking nest can have an accessible external entrance")
	if built:
		var new_home: House = first.registry.at(Vector2i(52, 54)) as House
		expect(not first.route_service.walkable(new_home.cell), "blocking footprint is closed")
		for resident in new_home.residents:
			var cell: Vector2i = first.route_service.world_to_cell(resident.global_position)
			expect(first.route_service.walkable(cell) and cell != new_home.cell, "residents spawn at an accessible entrance")
	var bad := House.new()
	var packed := PackedScene.new()
	packed.pack(bad)
	bad.free()
	var invalid := SceneBuildOption.new()
	invalid.scene = packed
	invalid.cost = entry(wood, 20)
	invalid.blocks_movement = false
	options.append(invalid)
	var stock_before: int = first.inventory.quantity(wood)
	expect(not first.build_controller.try_build(invalid, Vector2i(53, 54)), "invalid nest setup fails")
	expect(first.inventory.quantity(wood) == stock_before and first.registry.at(Vector2i(53, 54)) == null, "invalid setup leaves stock and world unchanged")
	var far: BuildOption = load("res://game/building/options/house.tres")
	expect(first.build_controller.check(far, Vector2i(18, 20)).code == PlacementCheck.Code.NO_ESCAPE, "nest with unreachable feeding rejected")
	var slow: SceneBuildOption = far.duplicate(true) as SceneBuildOption
	slow.spawn_speed = 1.0
	options.append(slow)
	expect(first.build_controller.check(slow, Vector2i(74, 50)).code == PlacementCheck.Code.NO_ESCAPE, "nest outside its movement profile budget rejected")
	var saved_available: int = first.inventory.available(food)
	first.inventory.try_spend(entry(food, saved_available))
	expect(first.build_controller.check(far, Vector2i(51, 53)).code == PlacementCheck.Code.SPAWN_FOOD, "nest needs food for its residents")
	first.free()
	second.free()
	await get_tree().process_frame
	var nested: World = WORLD.instantiate() as World
	nested.auto_start = false
	var nest_node: Node = nested.get_node("Home")
	nest_node.owner = null
	nested.remove_child(nest_node)
	var group := Node2D.new()
	nested.add_child(group)
	group.add_child(nest_node)
	add_child(nested)
	expect(nested.population.count() == 10 and nested.registry.all().size() == 7, "nested starting buildings follow the same registration path")
	nested.free()
	await get_tree().process_frame

func _test_assignment_load() -> void:
	var world: World = make_world()
	var added := 0
	for y in range(36, 56, 2):
		for x in range(36, 56, 2):
			var cell := Vector2i(x, y)
			if world.registry.at(cell) != null: continue
			var workplace := Workplace.new()
			workplace.output = world.inventory.type_by_id(&"wood")
			workplace.output_amount = 2
			workplace.position = world.route_service.cell_to_world(cell)
			workplace.setup(cell, null)
			world.buildings.add_child(workplace)
			world.registry.register(workplace)
			added += 1
	await get_tree().process_frame
	var ant: AntAgent = world.population.agents()[0]
	var searches_before: int = world.route_service.search_count
	var started: int = Time.get_ticks_usec()
	var assigned := 0
	for request in range(1000):
		var plan: WorkPlan = world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
		if plan != null:
			assigned += 1
			plan.workplace.release_worker(ant)
	var elapsed_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	expect(assigned == 1000, "one thousand assignments remain feasible with many POIs")
	expect(world.route_service.search_count == searches_before, "repeated assignments do not start new searches")
	metrics["assignment_load"] = {"requests": 1000, "workplaces": world.registry.workplaces().size(), "wall_ms": elapsed_ms, "new_searches": world.route_service.search_count - searches_before}
	world.free()
	await get_tree().process_frame

func make_rules(stock: WorldInventory) -> MatchController:
	var rules := MatchController.new()
	rules.match_duration = 30.0
	rules.target_amount = 100
	rules.tracked_types.assign(stock.registered_types())
	add_child(rules)
	rules.start(stock)
	return rules

func _test_rules() -> void:
	var wood: ResourceType = resource(&"wood")
	var food: ResourceType = resource(&"food")
	var stock := WorldInventory.new()
	stock.configure([entry(wood, 100), entry(food, 100)])
	var rules: MatchController = make_rules(stock)
	await get_tree().process_frame
	expect(rules.is_finished(), "initial goals evaluated immediately")
	rules.free()
	stock.configure([entry(wood, 100), entry(food, 10)])
	rules = make_rules(stock)
	stock.add(food, 90)
	stock.try_spend(entry(food, 100))
	await get_tree().process_frame
	expect(not rules.is_finished(), "intermediate stock does not latch a false victory")
	var results: Array[MatchSummary] = []
	rules.completed.connect(func(summary: MatchSummary): results.append(summary))
	rules._process(31.0)
	rules._process(31.0)
	expect(results.size() == 1 and not results[0].won and not get_tree().paused, "timeout produces one domain result without global pause")
	wood.display_name = "Same name"
	food.display_name = "Same name"
	var summary: MatchSummary = MatchSummary.capture(true, &"target_reached", 20, stock)
	expect(summary.resources.size() == 2 and summary.resources[0].type.id != summary.resources[1].type.id, "duplicate display names preserve separate resources")
	rules.free()
	stock.free()

func _test_art_resolution() -> void:
	var art: ArtCatalog = load("res://game/art/colony_art.tres") as ArtCatalog
	expect(art.validate().is_empty(), "default art catalog valid")
	for name in ["grass", "soil", "road", "water", "nest", "canteen", "berries", "timber", "stone"]:
		expect((art.get(name) as Texture2D).get_size() == Vector2(16, 16), "default game texture is 16x16")
	var replacement: ArtCatalog = art.duplicate() as ArtCatalog
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	replacement.grass = ImageTexture.create_from_image(image)
	var world: World = WORLD.instantiate() as World
	world.auto_start = false
	world.art = replacement
	add_child(world)
	expect(world.ready_for_play and world.art.tile_resolution() == 32, "32px replacement loads without gameplay edits")
	expect(is_equal_approx(world.route_service.cell_size(), 16.0), "texture resolution does not change physical cell size")
	var cell := Vector2i(49, 50)
	expect(world.route_service.world_to_cell(world.route_service.cell_to_world(cell)) == cell, "32px replacement preserves coordinate roundtrip")
	expect(world.population.count() == 10, "32px replacement preserves population")
	world.free()
	await get_tree().process_frame

func _test_simulation() -> void:
	var world: World = make_world()
	var deaths: Array[int] = [0]
	for ant in world.population.agents():
		ant.died.connect(func(_ant: Node2D, _cause: int): deaths[0] += 1)
	var work: Array[int] = [0]
	for ant in world.population.agents():
		ant.work_completed.connect(func(_ant: Node2D, _place: Node2D): work[0] += 1)
	var start_food: int = world.inventory.quantity(world.inventory.type_by_id(&"food"))
	var started: int = Time.get_ticks_usec()
	for step in range(60 * 180):
		for ant in world.population.agents():
			ant._physics_process(1.0 / 60.0)
		if step % 600 == 0:
			await get_tree().process_frame
	expect(deaths[0] == 0 and world.population.count() == 10, "three simulated minutes without hunger deaths")
	expect(work[0] > 40 and world.inventory.quantity(world.inventory.type_by_id(&"food")) > start_food, "ants complete work and replenish food")
	metrics["simulation"] = {"seconds": 180, "ants": world.population.count(), "deaths": deaths[0], "completed_cycles": work[0], "wall_ms": (Time.get_ticks_usec() - started) / 1000.0, "searches": world.route_service.search_count, "cache_hits": world.route_service.cache_hits}
	world.free()
	await get_tree().process_frame
