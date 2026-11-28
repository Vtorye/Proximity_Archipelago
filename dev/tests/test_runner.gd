extends Node
## Executable regressions: a failure changes the process exit code.
const WORLD := preload("res://game/worlds/maps/starter_island.tscn")
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
	if OS.get_cmdline_user_args().has("navigation-only"):
		_test_navigation()
		print("NAV REGRESSION ", JSON.stringify({"assertions": assertions, "failures": failures}))
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	seed(20261025)
	await preload("res://dev/tests/voyage_regressions.gd").new().run(self)
	await _test_translations()
	await _test_language_toggle()
	TranslationServer.set_locale("ru")
	_test_manifest()
	_test_stock()
	_test_composite_stock()
	_test_navigation()
	var islands = preload("res://dev/tests/island_regressions.gd").new()
	islands.run(self)
	islands.test_foodless_colonies(self)
	islands.test_physical_logistics(self)
	islands.test_multiple_bases(self)
	islands.test_orders(self)
	islands.test_canteen_delivery(self)
	await islands.test_authored_map(self)
	islands.test_recruitment(self)
	_test_resident_pruning()
	await _test_worlds()
	await preload("res://dev/tests/build_regressions.gd").new().run(self)
	await _test_assignment_lifecycle()
	await preload("res://dev/tests/planning_regressions.gd").new().run(self)
	await _test_assignment_load()
	await _test_rules()
	await _test_art_resolution()
	await _test_camera_settings()
	await preload("res://dev/tests/designer_regressions.gd").new().run(self)
	await preload("res://dev/tests/task_regressions.gd").new().run(self)
	await preload("res://dev/tests/construction_regressions.gd").new().run(self)
	await preload("res://dev/tests/combat_regressions.gd").new().run(self)
	await preload("res://dev/tests/terrain_regressions.gd").new().run(self)
	await _test_simulation()
	await _test_satiety_rules()
	await _test_level_editor_layout()
	await _test_match_conversation_without_scene_dialogue()
	print("TEST REPORT ", JSON.stringify({"assertions": assertions, "failures": failures, "metrics": metrics}))
	print("TESTS PASS" if failures.is_empty() else "TESTS FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_manifest() -> void:
	var manifest: Manifest = load("res://game/application/manifest.tres") as Manifest
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

func _test_composite_stock() -> void:
	var stone: ResourceType = resource(&"stone")
	var food: ResourceType = resource(&"food")
	var stock := WorldInventory.new()
	stock.configure([entry(stone, 5), entry(food, 20)])
	var notifications: Array[int] = [0]
	stock.changed.connect(func(): notifications[0] += 1)
	var price: Array[ResourceAmount] = [entry(stone, 5), entry(food, 21)]
	expect(not stock.try_spend_all(price), "unaffordable composite purchase fails")
	expect(stock.quantity(stone) == 5 and stock.quantity(food) == 20 and notifications[0] == 0, "failed composite purchase spends nothing and emits nothing")
	price = [entry(stone, 3), entry(stone, 3)]
	expect(not stock.can_afford_all(price), "duplicate price entries share the same stock budget")
	var ticket: StockReservation = stock.reserve(food)
	expect(not stock.try_spend_all([entry(stone, 5), entry(food, 20)]), "composite purchase cannot spend a reserved meal")
	stock.release(ticket)
	notifications[0] = 0
	var snapshots: Array[Vector2i] = []
	stock.changed.connect(func(): snapshots.append(Vector2i(stock.quantity(stone), stock.quantity(food))))
	expect(stock.try_spend_all([entry(stone, 2), entry(food, 20), entry(stone, 3)]), "composite purchase spends all resource types and duplicate entries")
	expect(notifications[0] == 1 and snapshots == [Vector2i.ZERO], "composite purchase observers see one fully committed state")
	expect(stock.try_spend_all([]) and notifications[0] == 1, "free purchase succeeds without a stock notification")
	for invalid in [[null], [entry(stone, -1)], [entry(resource(&"unknown"), 0)]]:
		var entries: Array[ResourceAmount] = []
		entries.assign(invalid)
		expect(not stock.try_spend_all(entries), "invalid composite component rejects the entire purchase")
	stock.free()

func _test_navigation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025
	for sample in range(15):
		var grid := TileGrid.new()
		var costs := PackedFloat32Array()
		for index in range(81):
			costs.append(0.0 if rng.randf() < 0.2 else [0.35, 1.0, 2.0][rng.randi_range(0, 2)])
		grid.configure(Rect2i(-2, -3, 9, 9), costs)
		_check_road_field_repair(grid)
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
	var updates := TileGrid.new()
	updates.configure(Rect2i(0, 0, 3, 2), PackedFloat32Array([1, 1, 1, 1, 1, 1]))
	var changed_cells: Array[Vector2i] = [Vector2i(1, 0)]
	for algorithm in [ASTAR.new(), DIJKSTRA.new()]:
		algorithm.build(updates)
		for value in [0.25, 2.0, 0.0, 1.0]:
			updates = updates.with_cost(Vector2i(1, 0), value)
			algorithm.update_grid(updates, changed_cells)
			expect(is_equal_approx(algorithm.get_cost(Vector2i.ZERO, Vector2i(2, 0)), _reference(updates, Vector2i.ZERO, Vector2i(2, 0))), "incremental terrain updates preserve optimal path cost")
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

func _check_road_field_repair(grid: TileGrid) -> void:
	var cells := grid.walkable_cells()
	if cells.is_empty(): return
	var seeds: Array[Vector2i] = [cells.front(), cells.back()]
	var next := grid
	var changed := PackedInt32Array()
	# Lower adjacent costs and costs on different components in one revision.
	for id in range(0, cells.size(), 4):
		next = next.with_cost(cells[id], next.cost(cells[id]) * 0.35)
		changed.append(id)
	for reverse in [false, true]:
		var repaired := GridSearch.build(grid, seeds, reverse)
		GridSearch.repair(repaired, next, changed)
		var fresh := GridSearch.build(next, seeds, reverse)
		var matches := true
		for cell in cells:
			var distance := fresh.cost(cell)
			if is_inf(distance):
				matches = matches and repaired.path(cell).is_empty()
				continue
			var path := repaired.path(cell)
			if path.is_empty():
				matches = false
				continue
			var path_cost := 0.0
			for step in range(1, path.size()):
				path_cost += next.cost(path[step])
			matches = matches and is_equal_approx(repaired.cost(cell), distance)
			matches = matches and is_equal_approx(path_cost, distance)
			if reverse:
				matches = matches and seeds.has(path.back()) and path.back() == repaired.destination(cell)
			else:
				matches = matches and seeds.has(path.front())
		expect(matches, "road repair preserves optimal weighted routes and seed reachability")

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

func make_world(satiety: SatietyRules = null) -> World:
	var world: World = WORLD.instantiate() as World
	if satiety != null:
		world.satiety_rules = satiety
	world.task_deck = null
	world.auto_start = false
	world.build_controller.physical_construction = false
	add_child(world)
	return world

func _test_satiety_rules() -> void:
	var rules := SatietyRules.new()
	rules.walk_rate = 2.5
	rules.rest_rate = 1.5
	rules.eat_rate = 0.75
	rules.meal_seconds = 3.0
	rules.safety_margin = 5.0
	var world := make_world(rules)
	var ant := world.population.agents()[0]
	var cell := world.route_service.world_to_cell(ant.global_position)
	var route := world.planner.food_route(cell)
	expect(route.is_valid(), "satiety fixture has a route to food")
	expect(ant.needs.rules == rules and world.planner.satiety_rules == rules, "planning and resident metabolism use the world's satiety resource")
	var escape := world.planner.escape_energy(cell, ant.speed)
	var expected := world.planner.travel_seconds(route.cost, ant.speed) * 2.5 + 3.0 * 0.75
	expect(is_equal_approx(escape, expected) and not world.planner.food_within_range(cell, ant.speed, escape + 4.0), "escape checks use the configured walk rate, meal cost, and safety margin")
	ant._timer = 1.0
	ant._physics_process(0.25)
	expect(is_equal_approx(ant.needs.capacity - ant.needs.satiety, 1.5 * 0.25), "rest spends energy at the configured rate")
	ant.needs.eat()
	ant._walk(route, &"food")
	ant._physics_process(0.25)
	expect(is_equal_approx(ant.needs.capacity - ant.needs.satiety, 2.5 * 0.25), "walking consumes energy at the rate quoted by the planner")
	ant._arrive()
	expect(ant.status == AntAgent.Status.EATING and is_equal_approx(ant._timer, 3.0), "meal duration comes from the world resource")
	world.free()
	await get_tree().process_frame

func _test_worlds() -> void:
	var first: World = make_world()
	var second: World = make_world()
	var map: TileMapLayer = first.get_node("Map")
	expect(first.map_size == Vector2i(50, 50) and map.get_used_rect() == Rect2i(0, 0, 50, 50) and map.get_used_cells().size() == 2500, "default world contains exactly fifty by fifty cells")
	for building in first.registry.all():
		expect(map.get_used_rect().has_point(building.cell) and first.route_service.walkable(building.entry_cells()[0]), "smaller world keeps every starting building inside the map and accessible")
	var field: NavigationField = first.route_service.food_field()
	metrics["navigation_50x50"] = {"field_bytes": field.costs.size() * 4 + field.parents.size(), "cells": map.get_used_cells().size()}
	expect(field.costs.size() <= first.route_service.snapshot().node_count() and field.costs.size() < 2500, "navigation fields contain land only; water has no distance entry")
	expect(first.population.count() == 5 and second.population.count() == 5, "worlds own independent ant populations")
	for ant in second.population.agents():
		expect(ant.get_parent() == second.units and ant.route_service == second.route_service and ant.planner.inventory == second.inventory, "second world has no first-world dependency")
	var house: House = second.get_node("Home") as House
	var origin: Vector2i = house.cell
	house.free()
	expect(second.registry.at(origin) == null and second.population.count() == 0, "external nest removal clears occupancy and residents")
	var food: ResourceType = first.inventory.type_by_id(&"food")
	var wood: ResourceType = first.inventory.type_by_id(&"wood")
	var ant: AntAgent = first.population.agents()[0]
	ant.needs.satiety = 12.0
	var plan: WorkPlan = first.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	expect(plan == null, "unsafe outward-work-return-food assignment rejected")
	ant.needs.eat()
	plan = first.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	expect(plan != null and plan.estimated_energy + ant.needs.safety_margin <= ant.needs.satiety, "healthy ant receives a complete feasible plan")
	if plan != null and plan.workplace != null: plan.workplace.release_worker(ant)
	var nest: SceneBuildOption = load("res://game/colony/nests/barracks.tres").duplicate(true) as SceneBuildOption
	nest.blocks_movement = true
	nest.costs = [entry(wood, 0)]
	first.build_controller.unlock_option(nest)
	var built: bool = first.build_controller.try_build(nest, Vector2i(27, 29))
	expect(built, "blocking nest can have an accessible external entrance")
	if built:
		var new_home: House = first.registry.at(Vector2i(27, 29)) as House
		expect(not first.route_service.walkable(new_home.cell), "blocking footprint is closed")
		var carriers := 0
		for resident: AntAgent in new_home.residents:
			if resident.role == AntAgent.Role.CARRIER:
				carriers += 1
			var cell: Vector2i = first.route_service.world_to_cell(resident.global_position)
			expect(first.route_service.walkable(cell) and cell != new_home.cell, "residents spawn at an accessible entrance")
		expect(new_home.residents.size() == 5 and carriers == 1, "a built nest spawns four workers and one carrier")
	var bad := House.new()
	var packed := PackedScene.new()
	packed.pack(bad)
	bad.free()
	var invalid := SceneBuildOption.new()
	invalid.scene = packed
	invalid.costs = [entry(wood, 20)]
	invalid.blocks_movement = false
	first.build_controller.unlock_option(invalid)
	var stock_before: int = first.inventory.quantity(wood)
	expect(not first.build_controller.try_build(invalid, Vector2i(28, 29)), "invalid nest setup fails")
	expect(first.inventory.quantity(wood) == stock_before and first.registry.at(Vector2i(28, 29)) == null, "invalid setup leaves stock and world unchanged")
	var far: BuildOption = load("res://game/colony/nests/barracks.tres")
	expect(first.build_controller.check(far, Vector2i(9, 10)).allowed(), "nest with unreachable feeding can be placed")
	var slow: SceneBuildOption = far.duplicate(true) as SceneBuildOption
	slow.spawn_speed = 1.0
	first.build_controller.unlock_option(slow)
	expect(first.build_controller.check(slow, Vector2i(39, 25)).allowed(), "slow nest outside its feeding budget can be placed")
	# A slower tile must not consume a hungry ant's last safe escape budget.
	map.set_cell(Vector2i(28, 26), 3, Vector2i(2, 0))
	first.route_service.rebuild(first.registry.blocked_cells())
	var from_cell: Vector2i = first.route_service.world_to_cell(ant.global_position)
	var current_escape: float = first.route_service.food_field().cost(from_cell)
	ant.needs.satiety = ant.planner.travel_energy(current_escape, ant.movement_speed()) + ant.needs.rules.meal_energy() + ant.needs.safety_margin + 0.1
	var ground: BuildOption = load("res://game/terrain/options/ground.tres")
	var before_terrain: Vector2i = (first.get_node("Map") as TileMapLayer).get_cell_atlas_coords(Vector2i(28, 26))
	expect(not first.build_controller.try_build(ground, Vector2i(28, 26)) and first.build_controller.last_result.code == PlacementCheck.Code.NO_ESCAPE, "terrain change cannot strand a hungry ant")
	expect((first.get_node("Map") as TileMapLayer).get_cell_atlas_coords(Vector2i(28, 26)) == before_terrain, "unsafe terrain edit leaves map unchanged")
	ant.needs.eat()
	var saved_available: int = first.inventory.available(food)
	first.inventory.try_spend(entry(food, saved_available))
	expect(first.build_controller.check(far, Vector2i(26, 28)).allowed(), "nest can be placed without free food portions")
	first.free()
	second.free()
	await get_tree().process_frame
	var nested: World = WORLD.instantiate() as World
	nested.auto_start = false
	nested.build_controller.physical_construction = false
	var nest_node: Node = nested.get_node("Home")
	nest_node.owner = null
	nested.remove_child(nest_node)
	var group := Node2D.new()
	nested.add_child(group)
	group.add_child(nest_node)
	add_child(nested)
	expect(nested.population.count() == 5 and nested.registry.all().size() == 6, "nested starting buildings follow the same registration path")
	nested.free()
	await get_tree().process_frame

func _test_assignment_load() -> void:
	var world: World = make_world()
	for y in range(11, 31, 2):
		for x in range(11, 31, 2):
			var cell := Vector2i(x, y)
			if world.registry.at(cell) != null: continue
			var workplace := Workplace.new()
			workplace.output = world.inventory.type_by_id(&"wood")
			workplace.output_per_second = 2.0
			workplace.position = world.route_service.cell_to_world(cell)
			workplace.setup(cell, null)
			world.buildings.add_child(workplace)
			world.registry.register(workplace)
	var preparation_started: int = Time.get_ticks_usec()
	world.planner.prepare_workplaces()
	var preparation_ms: float = (Time.get_ticks_usec() - preparation_started) / 1000.0
	await get_tree().process_frame
	var ant: AntAgent = world.population.agents()[0]
	var origins: Array[Vector2i] = []
	for y in range(22, 27):
		for x in range(22, 27):
			var cell := Vector2i(x, y)
			if world.route_service.snapshot().connected(ant.home.cell, cell):
				origins.append(cell)
	expect(not origins.is_empty(), "assignment load fixture includes reachable cells away from the nest")
	var searches_before: int = world.route_service.search_count
	var started: int = Time.get_ticks_usec()
	var assigned := 0
	var origin := world.planner.accessible_entry(ant.home)
	for _request in range(1000):
		ant.global_position = world.route_service.cell_to_world(origin)
		var plan: WorkPlan = world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
		if plan != null and plan.workplace != null:
			assigned += 1
			plan.workplace.release_worker(ant)
	var elapsed_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	expect(assigned == 1000, "one thousand assignments remain feasible with many workplaces")
	expect(world.route_service.search_count - searches_before <= 1 and world.planner._work_fields.size() == 1, "a thousand departures share one forward field")
	var away: Vector2i = origins.back()
	ant.global_position = world.route_service.cell_to_world(away)
	var replan := world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	expect(replan != null and replan.outward != null and replan.outward.cells.front() == away, "a worker replans from its real cell away from home")
	metrics["assignment_load"] = {"requests": 1000, "origins": origins.size(), "workplaces": world.registry.workplaces().size(), "work_fields": world.planner._work_fields.size(), "preparation_ms": preparation_ms, "wall_ms": elapsed_ms, "new_searches": world.route_service.search_count - searches_before}
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
	var art: ArtCatalog = load("res://graphics/catalog/colony_art.tres") as ArtCatalog
	expect(art.validate().is_empty(), "default art catalog valid")
	var replacement: ArtCatalog = art.duplicate() as ArtCatalog
	var resolution := art.tile_resolution() * 2
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	replacement.grass = ImageTexture.create_from_image(image)
	var world: World = WORLD.instantiate() as World
	world.auto_start = false
	world.build_controller.physical_construction = false
	world.art = replacement
	add_child(world)
	expect(world.ready_for_play and world.art.tile_resolution() == resolution and world.map.tile_set.tile_size == Vector2i(16, 16), "sprite catalog replacement preserves the authored map tile geometry")
	expect(is_equal_approx(world.route_service.cell_size(), 16.0), "texture resolution does not change physical cell size")
	var cell := Vector2i(24, 25)
	expect(world.route_service.world_to_cell(world.route_service.cell_to_world(cell)) == cell, "texture replacement preserves coordinate roundtrip")
	expect(world.population.count() == 5, "texture replacement preserves population")
	world.free()
	await get_tree().process_frame

func _test_camera_settings() -> void:
	var camera := WorldCamera.new()
	var settings := camera.get("settings") as Resource
	expect(settings != null, "camera uses editable zoom settings")
	if settings == null:
		camera.free()
		return
	settings = settings.duplicate()
	settings.set("zoom_steps", PackedFloat32Array([0.75, 1.5, 3.0]))
	settings.set("initial_level", 0)
	camera.set("settings", settings)
	add_child(camera)
	expect(camera.zoom.is_equal_approx(Vector2.ONE * 1.5), "camera initializes from its assigned settings")
	camera.set_level(99)
	expect(camera.zoom.is_equal_approx(Vector2.ONE * 3.0), "zoom clamps to the end of the configured steps")
	camera.set_level(-99)
	expect(camera.zoom.is_equal_approx(Vector2.ONE * 0.75), "zoom clamps to the start of the configured steps")
	camera.queue_free()
	await get_tree().process_frame

func _test_simulation() -> void:
	var scenarios := {}
	for roads in [false, true]:
		seed(20261025)
		var world: World = make_world()
		var barracks: BuildOption = preload("res://game/colony/nests/barracks.tres")
		var timber_camp := Vector2i(21, 23)
		var timber_camp_built := false
		if roads:
			var road: BuildOption = load("res://game/terrain/options/road.tres")
			var network: Array[Vector2i] = []
			for x in range(21, 30): network.append(Vector2i(x, 25))
			for item in [Vector3i(21, 22, 24), Vector3i(24, 21, 24), Vector3i(29, 21, 24), Vector3i(28, 26, 26)]:
				for y in range(item.y, item.z + 1): network.append(Vector2i(item.x, y))
			for cell in network:
				expect(world.build_controller.try_build(road, cell), "safe road network can be built from starting stock")
			expect(world.build_controller.try_build(barracks, Vector2i(29, 22)), "player can place another nest near the stone workplace")
		var deaths: Array[int] = [0]
		var work: Array[int] = [0]
		world.population.spawned.connect(func(ant: AntAgent):
			ant.died.connect(func(_ant: Node2D, _cause: int): deaths[0] += 1)
			ant.work_completed.connect(func(_ant: Node2D, _place: Node2D): work[0] += 1))
		for ant in world.population.agents():
			ant.died.connect(func(_ant: Node2D, _cause: int): deaths[0] += 1)
			ant.work_completed.connect(func(_ant: Node2D, _place: Node2D): work[0] += 1)
		var outcomes: Array[MatchSummary] = []
		world.match_controller.completed.connect(func(summary: MatchSummary): outcomes.append(summary))
		world.match_controller.start(world.inventory)
		var started: int = Time.get_ticks_usec()
		for step in range(60 * 180 + 1):
			for ant in world.population.agents(): ant._physics_process(1.0 / 60.0)
			world.match_controller._process(1.0 / 60.0)
			if step % 60 == 0:
				if roads and not timber_camp_built:
					timber_camp_built = world.build_controller.try_build(barracks, timber_camp)
				await get_tree().process_frame
			if world.match_controller.is_finished(): break
		expect(deaths[0] == 0 and world.population.count() == (15 if roads else 5), "full match has no starvation deaths and the developed colony opens both camps")
		expect(outcomes.size() == 1 and outcomes[0].won == roads, "idle loses; roads and purposeful nest placement win within three minutes")
		var stock := {}
		for type in world.inventory.registered_types(): stock[String(type.id)] = world.inventory.quantity(type)
		scenarios["roads" if roads else "idle"] = {"seconds": 180.0 - world.match_controller.time_remaining, "ants": world.population.count(), "deaths": deaths[0], "completed_cycles": work[0], "stock": stock, "won": not outcomes.is_empty() and outcomes[0].won, "wall_ms": (Time.get_ticks_usec() - started) / 1000.0, "searches": world.route_service.search_count, "cache_hits": world.route_service.cache_hits}
		world.free()
		await get_tree().process_frame
	metrics["simulation"] = scenarios

func _test_assignment_lifecycle() -> void:
	var world: World = make_world()
	var ant: AntAgent = world.population.agents()[0]
	for workplace in world.registry.workplaces(): workplace.work_slots = 0
	var food: ResourceType = world.inventory.type_by_id(&"food")
	var before: int = world.inventory.quantity(food)
	ant._decide()
	expect(ant.status == AntAgent.Status.HOME and ant.work.plan.waiting_for_slot, "busy work slots leave a healthy ant waiting at home")
	expect(ant._meal.active and world.inventory.quantity(food) == before, "waiting preserves the next reserved meal")
	for workplace in world.registry.workplaces(): workplace.work_slots = 4
	ant._decide()
	var job: Workplace = ant.work.workplace
	expect(job != null and ant.status == AntAgent.Status.WALKING, "released work slots allow a new assignment")
	job.demolish()
	job.free()
	expect(ant.work.workplace == null and ant._destination != &"work", "removed workplace immediately cancels the walking assignment")
	world.free()
	await get_tree().process_frame

func _test_translations() -> void:
	var original_locale := TranslationServer.get_locale()
	var csv := FileAccess.open("res://visual_novel/localization/keys.csv", FileAccess.READ)
	var header := csv.get_csv_line()
	var rows: Array[PackedStringArray] = []
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() == header.size():
			rows.append(row)
	var scene_paths := [
		"res://game/application/menus/main_menu.tscn",
		"res://visual_novel/ui/story_overlay.tscn",
		"res://game/application/menus/settings_menu.tscn",
		"res://game/match/pause_menu.tscn",
		"res://game/match/match_result.tscn",
	]
	for column in [1, 2]:
		TranslationServer.set_locale(header[column])
		for row in rows:
			expect(TranslationServer.translate(row[0]) == row[column].c_unescape(), "translation matches CSV: %s / %s" % [header[column], row[0]])
		for scene_path: String in scene_paths:
			var screen: Control = load(scene_path).instantiate()
			add_child(screen)
			await get_tree().process_frame
			for control in screen.find_children("*", "Control", true, false):
				if control is Label or control is Button:
					var text: String = control.text
					if text.begins_with("ui."):
						expect(control.atr(text) != text, "screen label resolves: " + text)
			screen.queue_free()
			await get_tree().process_frame
	TranslationServer.set_locale(original_locale)

func _test_language_toggle() -> void:
	var original_locale := TranslationServer.get_locale()
	var original_language := AppSettings.language
	var menu: Control = load("res://game/application/menus/main_menu.tscn").instantiate()
	add_child(menu)
	TranslationServer.set_locale("en")
	for expected in ["ru", "en"]:
		menu.controls[&"language"].pressed.emit()
		await get_tree().process_frame
		expect(TranslationServer.get_locale() == expected, "language button switches the active locale")
		var button: Button = menu.controls[&"language"]
		expect(button.atr(button.text) == ("Язык: Русский" if expected == "ru" else "Language: English"), "language button updates its caption immediately")
		var play: Button = menu.controls[&"play"]
		expect(play.atr(play.text) == TranslationServer.translate("ui.menu.play"), "existing menu actions use the selected language")
		var saved := ConfigFile.new()
		expect(saved.load(AppSettings.PATH) == OK and saved.get_value("interface", "language") == expected, "language selection is persisted")
	menu.queue_free()
	await get_tree().process_frame
	AppSettings.language = original_language
	AppSettings.save()
	TranslationServer.set_locale(original_locale)

func _test_level_editor_layout() -> void:
	var previous_size := AppSettings.text_size
	AppSettings.text_size = AppSettings.TYPOGRAPHY.minimum_sizes.size() - 1
	AppSettings.apply()
	var editor: Control = preload("res://game/worlds/editor/level_editor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport := get_viewport().get_visible_rect()
	var top: Control = editor.get_node("%Top")
	var bottom: Control = editor.get_node("%Bottom")
	expect(viewport.encloses(top.get_global_rect()) and viewport.encloses(bottom.get_global_rect())
		and top.get_global_rect().end.y < bottom.get_global_rect().position.y, "map editor toolbars fit at the largest text size")
	var workplace := editor._objects.get_node("Workplace") as Workplace
	var sprite := workplace.get_node("Sprite") as Sprite2D
	expect((sprite.texture.get_size() * sprite.scale).is_equal_approx(Vector2(editor._map.tile_set.tile_size)), "map editor scales building artwork to the tile footprint")
	var open: Button = editor.get_node("%OpenGeneration")
	editor._open_options(open, true)
	await get_tree().process_frame
	var submit: Button = editor.get_node("%GenerateMap")
	expect(submit.is_visible_in_tree() and viewport.encloses(submit.get_global_rect()), "generation opens with its submit button on screen")
	editor._close_options()
	expect(get_viewport().gui_get_focus_owner() == open, "closing map options restores keyboard focus")
	editor.free()
	AppSettings.text_size = previous_size
	AppSettings.apply()

func _test_match_conversation_without_scene_dialogue() -> void:
	var screen = preload("res://game/match/match.tscn").instantiate()
	screen.payload = LevelStore.load_level("builtin/tidal_shards")
	var story: StoryOverlay = screen.get_node("StoryLayer/Story")
	story.dialogue_resource = null
	add_child(screen)
	screen.on_focus()
	screen.hud.section_requested.emit(&"talk")
	for frame in range(3):
		await get_tree().process_frame
	for button: Button in screen.conversations.get_node("%People").get_children():
		var character := button.get_meta(&"character") as StoryCharacter
		if character.id == &"Queen":
			expect(button.is_visible_in_tree(), "Queen is available in ordinary match conversations")
			button.pressed.emit()
			break
	for frame in range(3):
		await get_tree().process_frame
	var line: Label = story.get_node("%Dialogue")
	expect(story.is_modal and line.text == tr("ui.chapter.resource_question"),
		"ordinary match opens the Queen's topic with no dialogue assigned in the scene")
	screen.on_blur()
	screen.queue_free()
	await get_tree().process_frame
