extends RefCounted
func run(test: Node) -> void:
	var land: Dictionary[Vector2i, float] = {}
	for origin in [Vector2i.ZERO, Vector2i(1000000, 1000000)]:
		for x in range(32):
			for y in range(32): land[origin + Vector2i(x, y)] = 1.0
	var grid := TileGrid.new()
	var before: int = Time.get_ticks_usec()
	grid.configure_sparse(Rect2i(0, 0, 1000032, 1000032), land)
	var service := RouteService.new()
	service.configure_grid(grid)
	var field: NavigationField = service.distances_from(Vector2i.ZERO)
	test.expect(grid.node_count() == 2048 and grid.component_count() == 2, "a trillion-cell bounding box stores only its 2048 land nodes")
	test.expect(field.costs.size() == 1024 and field.parents.size() == 1024, "a source field allocates only its connected island")
	test.expect(field.cost(Vector2i(31, 31)) == 62 and is_inf(field.cost(Vector2i(1000000, 1000000))), "component-local distances preserve reachability")
	var searches: int = service.search_count
	test.expect(is_inf(service.get_path_cost(Vector2i.ZERO, Vector2i(1000000, 1000000))) and service.request_route(Vector2i.ZERO, Vector2i(1000000, 1000000)).cells.is_empty() and service.search_count == searches, "disconnected requests reject before running a search")
	var reverse: NavigationField = service.reverse_field([Vector2i(31, 31), Vector2i(1000031, 1000031)])
	test.expect(reverse.cost(Vector2i.ZERO) == 62 and reverse.cost(Vector2i(1000000, 1000000)) == 62, "multi-source food fields cover each seeded component")
	test.expect(GridSearch.build(grid, [Vector2i(400, 400)]).costs.is_empty(), "water seeds allocate no field")
	test.metrics["sparse_islands"] = {"bounds": str(grid.rect().size), "land_nodes": grid.node_count(), "components": grid.component_count(), "field_nodes": field.costs.size(), "field_distance_parent_bytes": field.costs.size() * 4 + field.parents.size(), "setup_and_cold_ms": (Time.get_ticks_usec() - before) / 1000.0}
	service.free()
	var bridge := TileGrid.new()
	bridge.configure(Rect2i(-2, -1, 5, 1), PackedFloat32Array([1, 1, 0, 1, 1]))
	var joined: TileGrid = bridge.with_cost(Vector2i(0, -1), 0.25)
	test.expect(bridge.component_count() == 2 and joined.component_count() == 1 and joined.connected(Vector2i(-2, -1), Vector2i(2, -1)), "opening a bridge merges components without mutating the old snapshot")
	var split: TileGrid = joined.with_cost(Vector2i(0, -1), 0.0)
	test.expect(split.component_count() == 2 and not split.connected(Vector2i(-2, -1), Vector2i(2, -1)), "closing a bridge splits components")
	test.expect(GridSearch.build(joined, [Vector2i(-2, -1)]).cost(Vector2i(2, -1)) == 3.25, "a new cheap bridge preserves entry costs")
	var routes := RouteService.new()
	routes.configure_grid(bridge)
	var registry := BuildingRegistry.new()
	var planner := TripPlanner.new()
	var stock := WorldInventory.new()
	planner.configure(registry, routes, stock, null)
	var a := Workplace.new()
	var b := Workplace.new()
	a.setup(Vector2i(-2, -1), null)
	b.setup(Vector2i(2, -1), null)
	registry.register(a)
	registry.register(b)
	test.expect(planner._reachable_workplaces(routes.snapshot().index(a.cell)) == [a], "assignment candidates exclude another island")
	var field_a: NavigationField = planner._work_fields[a.cell]
	var field_b: NavigationField = planner._work_fields[b.cell]
	test.expect(field_a.costs.size() == 2 and field_b.costs.size() == 2 and is_inf(field_b.cost_at_node(bridge.index(a.cell))), "each job stores distances only for its connected island")
	routes.configure_grid(joined)
	test.expect(planner._reachable_workplaces(routes.snapshot().index(a.cell)).size() == 2, "opening a bridge refreshes assignment component membership")
	field_b = planner._work_fields[b.cell]
	test.expect(is_equal_approx(field_b.cost_at_node(joined.index(a.cell)), 3.25) and field_b.path(a.cell).back() == b.cell, "a workplace field returns the weighted approach cost and route from the querying node")
	routes.configure_grid(split)
	test.expect(planner._reachable_workplaces(routes.snapshot().index(a.cell)) == [a], "closing a bridge removes disconnected candidates")
	field_a = planner._work_fields[a.cell]
	var searches_before: int = routes.search_count
	var removed_cell: Vector2i = b.cell
	b.demolish()
	b.free()
	test.expect(planner._reachable_workplaces(routes.snapshot().index(removed_cell)).is_empty(), "workplace removal invalidates candidate lists immediately")
	test.expect(planner._work_fields[a.cell] == field_a and not planner._work_fields.has(removed_cell) and routes.search_count == searches_before, "removing a job releases its field without rebuilding existing job fields")
	a.demolish()
	a.free()
	planner.free()
	registry.free()
	stock.free()
	routes.free()

func test_foodless_colonies(test: Node) -> void:
	var tiles: Array = []
	var working_nest := Vector2i(1, 1)
	var idle_nest := Vector2i(11, 1)
	var job_cell := Vector2i(3, 1)
	for start_x in [0, 10]:
		for x in range(start_x, start_x + 4):
			for y in range(3):
				tiles.append([x, y, 3, 0, 0, 0])
	var stranded_nest := Vector2i(20, 1)
	tiles.append([stranded_nest.x, stranded_nest.y, 3, 0, 0, 0])
	var objects := [[idle_nest.x, idle_nest.y, "Home"], [job_cell.x, job_cell.y, "Workplace"], [stranded_nest.x, stranded_nest.y, "Home"]]
	var layout := {"version": LevelLayout.VERSION, "tiles": tiles, "objects": objects}
	var title := "Foodless islands test " + str(OS.get_process_id())
	var filename: String = title.sha256_text() + ".json"
	test.expect(LevelStore.save_level(title, layout) == OK, "save a map with no canteens")
	var world: World = LevelLayout.create_world(LevelStore.load_level(filename))
	DirAccess.remove_absolute(LevelStore.DIRECTORY.path_join(filename))
	test.expect(world != null, "restore a map with no canteens")
	if world == null:
		return
	for index in range(world.starting_resources.size()):
		var entry: ResourceAmount = world.starting_resources[index]
		if entry.type.id == &"food":
			world.starting_resources[index] = test.entry(entry.type, 0)
	test.expect(LevelValidator.validate_world(world, title).is_empty(), "validator accepts nests and workplaces without canteens or starting food")
	world.auto_start = false
	test.add_child(world)
	var stock: WorldInventory = world.inventory
	var wood: ResourceType = stock.type_by_id(&"wood")
	var nest: BuildOption = preload("res://game/building/options/house.tres")
	var draft := BuildDraft.new()
	draft.controller = world.build_controller
	test.expect(draft.paint(nest, working_nest) and draft.budget_check().allowed() and draft.commit(), "build a nest on a dry island with work")
	var second_idle_nest := Vector2i(13, 2)
	test.expect(world.build_controller.try_build(nest, second_idle_nest), "build a nest on a dry island without work while other ants are stranded")
	var start_wood: int = stock.quantity(wood)
	var work_house := world.registry.at(working_nest) as House
	var idle_house := world.registry.at(second_idle_nest) as House
	if work_house == null or idle_house == null or work_house.residents.is_empty() or idle_house.residents.is_empty():
		test.expect(false, "both dry nests spawn residents")
		world.free()
		return
	var worker := work_house.residents[0] as AntAgent
	var wanderer := idle_house.residents[0] as AntAgent
	var stranded_house := world.registry.at(stranded_nest) as House
	var stranded := stranded_house.residents[0] as AntAgent
	var workplace := world.registry.at(job_cell) as Workplace
	var walked: Array[Vector2i] = []
	var deaths: Array[int] = []
	var idle_deaths: Array[int] = []
	for ant in [wanderer, stranded]:
		ant.died.connect(func(_ant: Node2D, cause: int): idle_deaths.append(cause))
	worker.died.connect(func(_ant: Node2D, cause: int): deaths.append(cause))
	wanderer.cell_changed.connect(func(_old: Vector2i, next: Vector2i): walked.append(next))
	worker._decide()
	wanderer._decide()
	stranded._decide()
	test.expect(stranded.status == AntAgent.Status.WANDERING and stranded.motion.route == null, "isolated ant waits if there are no walkable neighbors")
	test.expect(worker._destination == &"work" and workplace.incoming_count() == 1 and worker._meal == null, "dry ant leaves its nest and immediately reserves a job slot without a meal")
	test.expect(wanderer._destination == &"wander" and wanderer.current_workplace == null, "idle ant leaves its nest to wander instead of choosing work across water")
	var cycles: Array[int] = [0]
	worker.work_completed.connect(func(_ant: Node2D, _job: Node2D): cycles[0] += 1)
	for step in range(30 * 12):
		for ant in [worker, wanderer, stranded]:
			ant._physics_process(1.0 / 30.0)
		if step == 90:
			test.expect(workplace.working_count() == 1 and worker.status == AntAgent.Status.WORKING, "dry ant reaches the workplace")
	test.expect(stock.quantity(wood) > start_wood, "dry worker carries the first batch to its local nest")
	test.expect(walked.size() >= 2 and wanderer.needs.satiety < AntNeeds.CAPACITY, "idle ant visits neighboring cells while losing satiety")
	test.expect(walked.all(func(cell: Vector2i) -> bool:
		return world.route_service.walkable(cell) and absi(cell.x - second_idle_nest.x) + absi(cell.y - second_idle_nest.y) <= 2), "wander stays on walkable cells near the nest")
	for step in range(30 * (ceili(world.match_controller.match_duration) - 12) - 1):
		for ant in [worker, wanderer, stranded]:
			ant._physics_process(1.0 / 30.0)
	test.expect(cycles[0] > 1 and deaths == [AntAgent.DeathCause.STARVATION], "dry worker continues producing and delivering until starvation")
	test.expect(workplace.worker_count() == 0 and not work_house.residents.has(worker), "starvation releases the work slot and nest resident")
	test.expect(idle_deaths == [AntAgent.DeathCause.STARVATION, AntAgent.DeathCause.STARVATION], "both wandering and stationary ants without food starve before a standard match ends")
	test.expect(not idle_house.residents.has(wanderer) and not stranded_house.residents.has(stranded), "idle starvation removes residents from their nests")
	var successor := work_house.residents[0] as AntAgent
	successor._decide()
	for step in range(90):
		successor._physics_process(1.0 / 30.0)
	var food: ResourceType = stock.type_by_id(&"food")
	stock.add(food, 1)
	test.expect(successor.status == AntAgent.Status.WORKING and stock.available(food) == 1, "isolated workers leave global food unreserved")
	var canteen: BuildOption = preload("res://game/building/options/canteen.tres")
	if not world.build_controller.options.has(canteen):
		world.build_controller.options.append(canteen)
	stock.add(stock.type_by_id(&"royal"), 3)
	test.expect(world.build_controller.try_build(canteen, job_cell + Vector2i.UP), "new canteen restores access to food on the working island")
	successor._reconsider_route()
	test.expect(successor._destination == &"food" and successor._meal != null and workplace.worker_count() == 0, "worker switches to a reachable meal when a canteen opens")
	for step in range(90):
		successor._physics_process(1.0 / 30.0)
	test.expect(stock.quantity(food) == 0 and successor.needs.satiety > 119.0, "restored meal replenishes the worker's satiety")
	for step in range(150):
		successor._physics_process(1.0 / 30.0)
	test.expect(successor.status == AntAgent.Status.WAITING_FOR_FOOD, "ant waits for food when the accessible canteen runs out")
	var waiting_deaths: Array[int] = []
	successor.died.connect(func(_ant: Node2D, cause: int): waiting_deaths.append(cause))
	for step in range(30 * ceili(world.match_controller.match_duration) - 1):
		successor._physics_process(1.0 / 30.0)
	test.expect(waiting_deaths == [AntAgent.DeathCause.STARVATION], "waiting at an empty canteen still leads to starvation within a match")
	var fed_idle := work_house.residents[0] as AntAgent
	workplace.work_slots = 0
	stock.add(food, 1)
	for step in range(30 * ceili(world.match_controller.match_duration)):
		fed_idle._physics_process(1.0 / 30.0)
	test.expect(stock.quantity(food) == 0 and fed_idle.status != AntAgent.Status.DEAD, "an idle ant survives if it can reach and eat its reserved meal")
	world.free()

func test_physical_logistics(test: Node) -> void:
	var tiles: Array = []
	for x in range(11):
		for y in range(3):
			tiles.append([x, y, 3, 0, 0, 0])
	var world: World = LevelLayout.create_world({"version": LevelLayout.VERSION, "tiles": tiles,
		"objects": [[0, 1, "Home"], [6, 1, "Home"], [9, 1, "Home"], [7, 1, "Workplace"], [1, 1, "Food"]]})
	world.auto_start = false
	test.add_child(world)
	var stock: WorldInventory = world.inventory
	var main := world.registry.at(Vector2i(0, 1)) as House
	var depot := world.registry.at(Vector2i(6, 1)) as House
	var other := world.registry.at(Vector2i(9, 1)) as House
	var job := world.registry.at(Vector2i(7, 1)) as Workplace
	var wood: ResourceType = stock.type_by_id(&"wood")
	var stone: ResourceType = stock.type_by_id(&"stone")
	var food: ResourceType = stock.type_by_id(&"food")
	depot.storage_capacity = 5
	job.output_amount = 5
	test.expect(world.logistics.main_nest == main and not world.build_controller.demolition_check(main.cell).allowed(), "the first nest is the single protected construction center")
	var ant := main.residents[0] as AntAgent
	ant.global_position = world.route_service.cell_to_world(job.cell)
	ant._decide()
	ant._physics_process(0.05)
	var before: int = stock.quantity(wood)
	ant._physics_process(ant.work_time)
	test.expect(WorldInventory.cargo_size(ant.cargo) == ant.carry_capacity and stock.quantity(wood) == before and job.worker_count() == 0, "production loads only what the ant can carry and credits nothing before delivery")
	_step_until(ant, func() -> bool: return ant.cargo.is_empty())
	test.expect(stock.depot_quantity(depot, wood) == 2 and stock.main_quantity(wood) == before and stock.quantity(wood) == before + 2, "the nearest depot receives the physical cargo and counts toward colony totals")
	var central_price: Array[ResourceAmount] = [test.entry(wood, before + 1)]
	test.expect(stock.can_afford_all(central_price) and not stock.can_afford_all(central_price, true), "construction cannot spend timber stored outside the main nest")
	test.expect(stock.deposit(depot, [test.entry(stone, 1)]), "mixed resources occupy the same depot")
	ant.global_position = world.route_service.cell_to_world(job.cell)
	ant.cargo = job.take_output(ant.carry_capacity)
	ant._deliver()
	test.expect(ant._delivery_nest == depot and stock.deposit(depot, [test.entry(food, 2)]), "another delivery can fill the chosen depot while a carrier is moving")
	test.expect(stock.depot_fill(depot) == 5 and not stock.deposit(depot, [test.entry(stone, 1)]) and not world.build_controller.demolition_check(depot.cell).allowed(), "a full depot rejects additional stock and cannot be demolished")
	ant.needs.satiety = 11.0
	for step in range(90):
		ant._physics_process(1.0 / 60.0)
		if ant._destination == &"food":
			break
	test.expect(ant._main_delivery and ant._destination == &"food" and WorldInventory.cargo_size(ant.cargo) == 2, "a rejected carrier keeps the cargo and goes to eat before continuing to the main nest")
	_step_until(ant, func() -> bool: return ant.cargo.is_empty())
	test.expect(stock.main_quantity(wood) == before + 2 and stock.depot_fill(other) == 0, "rejected cargo goes to the main nest rather than another small nest")
	var courier := main.residents.back() as AntAgent
	test.expect(courier.role == AntAgent.Role.CARRIER and courier.speed > ant.speed and courier.carry_capacity > ant.carry_capacity, "main nest spawns a faster carrier with a larger load")
	test.expect(world.planner.plan_work(courier, main, courier.needs, courier.speed, courier.work_time, courier._meal) == null and not job.reserve_worker(courier), "a carrier cannot get a production assignment or take a worker slot")
	test.expect(depot.dispatch_threshold == 70 and depot.auto_dispatch, "local depots default to automatic dispatch at seventy percent")
	depot.auto_dispatch = false
	test.expect(not world.logistics.ready_to_dispatch(depot), "automatic dispatch can be disabled per depot")
	depot.auto_dispatch = true
	depot.dispatch_threshold = 90
	var total: int = stock.quantity(wood)
	var main_before: int = stock.main_quantity(wood)
	courier._decide()
	test.expect(courier._destination == &"pickup" and courier._pickup_source == depot and courier.cargo.is_empty(), "the main carrier walks to an eligible remote depot before loading")
	_step_until(courier, func() -> bool: return courier._shipment)
	test.expect(courier._shipment and courier._delivery_nest == main and WorldInventory.cargo_size(courier.cargo) == 5, "the carrier loads multiple resource types and delivers only to the main nest")
	test.expect(stock.quantity(wood) == total and stock.main_quantity(wood) == main_before and stock.depot_quantity(depot, wood) == 0, "dispatched cargo counts in totals during transport but cannot be spent centrally")
	_step_until(courier, func() -> bool: return courier.cargo.is_empty())
	test.expect(stock.quantity(wood) == total and stock.main_quantity(wood) == main_before + 2, "shipment arrival moves stock without counting it twice")
	test.expect(not world.logistics.ready_to_dispatch(depot), "a depot below its configured threshold stops dispatching")
	courier._decide()
	test.expect(courier._pickup_source == job, "a carrier can collect production already waiting at a workplace")
	_step_until(courier, func() -> bool: return not courier.cargo.is_empty())
	test.expect(WorldInventory.cargo_size(courier.cargo) == 1 and job.pending_output_amount() == 0 and job.worker_count() == 0 and stock.quantity(wood) == total, "collecting surplus neither produces new goods nor occupies a work slot")
	_step_until(courier, func() -> bool: return courier.cargo.is_empty())
	test.expect(stock.quantity(wood) == total + 1 and stock.depot_quantity(depot, wood) == 1, "the carrier physically delivers workshop surplus to the nearest depot")
	world.free()

func _step_until(ant: AntAgent, condition: Callable) -> void:
	for step in range(1800):
		if condition.call() or ant.status == AntAgent.Status.DEAD:
			return
		ant._physics_process(1.0 / 60.0)

func test_recruitment(test: Node) -> void:
	var world: World = test.make_world()
	var main: House = world.logistics.main_nest
	var population: ColonyPopulation = world.population
	var stock: WorldInventory = world.inventory
	var food: ResourceType = stock.type_by_id(&"food")
	test.expect(main.residents.size() == 5 and main.resident_limit() == 20, "main nest starts with five residents and room for twenty")
	stock.try_spend(test.entry(food, stock.available(food)))
	var before: int = stock.quantity(food)
	test.expect(not population.recruit(main, AntAgent.Role.WORKER) and stock.quantity(food) == before and main.residents.size() == 5, "unaffordable recruitment leaves residents and stock intact")
	stock.add(food, 300)
	var nested_recruits: Array[bool] = []
	population.spawned.connect(func(_ant: AntAgent):
		nested_recruits.append(population.recruit(main, AntAgent.Role.CARRIER)))
	for index in range(15):
		var role: AntAgent.Role = AntAgent.Role.WORKER if index % 2 == 0 else AntAgent.Role.CARRIER
		before = stock.quantity(food)
		var price: int = BuildController.price_amount(world.recruitment.price(role), food)
		test.expect(population.recruit(main, role) and stock.quantity(food) == before - price, "each recruit is spawned after exactly one price payment")
	test.expect(main.residents.size() == 20 and nested_recruits.size() == 15 and not nested_recruits.has(true), "reentrant requests cannot exceed the twenty-resident limit")
	before = stock.quantity(food)
	test.expect(not population.recruit(main, AntAgent.Role.WORKER) and stock.quantity(food) == before, "a full main nest rejects a purchase without spending")
	var dead := main.residents[0] as AntAgent
	dead.die(AntAgent.DeathCause.STARVATION)
	test.expect(population.recruit(main, AntAgent.Role.CARRIER) and main.residents.size() == 20, "a resident death frees one slot for recruitment")
	var recruited := main.residents.back() as AntAgent
	test.expect(recruited.home == main and recruited.role == AntAgent.Role.CARRIER and recruited.speed == 36.0 and recruited.carry_capacity == 6, "recruited carriers belong to the selected nest and retain their role parameters")
	var nest: BuildOption = load("res://game/building/options/house.tres")
	test.expect(world.build_controller.try_build(nest, Vector2i(30, 29)), "recruitment fixture creates a small nest")
	var local := world.registry.at(Vector2i(30, 29)) as House
	test.expect(local.resident_limit() == 5 and not population.recruit(local, AntAgent.Role.WORKER), "small nests preserve their five-resident capacity")
	world.free()
