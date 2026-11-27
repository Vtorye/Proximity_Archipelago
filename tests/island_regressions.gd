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
	var cheaper := joined.with_cost(Vector2i(1, -1), 0.5)
	test.expect(joined.cost(Vector2i(1, -1)) == 1.0 and cheaper.cost(Vector2i(1, -1)) == 0.5 and cheaper.index(Vector2i(1, -1)) == joined.index(Vector2i(1, -1)), "cost-only edits preserve the old snapshot and reuse node indices")
	test.expect(reverse.destination(Vector2i.ZERO) == Vector2i(31, 31) and reverse.destination(Vector2i(1000000, 1000000)) == Vector2i(1000031, 1000031), "flow endpoints match the selected seed on each island")
	var routes := RouteService.new()
	routes.configure_grid(bridge)
	var registry := BuildingRegistry.new()
	var planner := TripPlanner.new()
	var stock := WorldInventory.new()
	planner.configure(registry, routes, stock, null, null, SatietyRules.new())
	var a := Workplace.new()
	var b := Workplace.new()
	a.output = test.resource(&"wood")
	b.output = a.output
	a.setup(Vector2i(-2, -1), null)
	b.setup(Vector2i(2, -1), null)
	registry.register(a)
	registry.register(b)
	test.expect(planner._reachable_workplaces(routes.snapshot().index(a.cell)) == [a], "assignment candidates exclude another island")
	test.expect(planner._work_fields.is_empty(), "indexing jobs does not run path searches")
	var field_a: NavigationField = planner._work_field(a.cell)
	test.expect(field_a.costs.size() == 2 and is_inf(field_a.cost(b.cell)), "a departure field stores only its connected island")
	routes.configure_grid(joined)
	test.expect(planner._reachable_workplaces(routes.snapshot().index(a.cell)).size() == 2, "opening a bridge refreshes assignment component membership")
	field_a = planner._work_field(a.cell)
	test.expect(is_equal_approx(field_a.cost(b.cell), 3.25) and field_a.path(b.cell).front() == a.cell, "a departure field returns weighted paths from the nest")
	routes.configure_grid(split)
	test.expect(planner._reachable_workplaces(routes.snapshot().index(a.cell)) == [a], "closing a bridge removes disconnected candidates")
	field_a = planner._work_field(a.cell)
	var searches_before: int = routes.search_count
	var removed_cell: Vector2i = b.cell
	b.demolish()
	b.free()
	test.expect(planner._reachable_workplaces(routes.snapshot().index(removed_cell)).is_empty(), "workplace removal invalidates candidate lists immediately")
	test.expect(planner._work_field(a.cell) == field_a and routes.search_count == searches_before, "removing a job does not rebuild departure fields")
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
	world.starting_resources = world.get_starting_resources().duplicate()
	for index in range(world.starting_resources.size()):
		var entry: ResourceAmount = world.starting_resources[index]
		if entry.type.id == &"food":
			world.starting_resources[index] = test.entry(entry.type, 0)
	test.expect(LevelValidator.validate_world(world, title).is_empty(), "validator accepts nests and workplaces without canteens or starting food")
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	var stock: WorldInventory = world.inventory
	var wood: ResourceType = stock.type_by_id(&"wood")
	var nest: BuildOption = preload("res://game/building/options/barracks.tres")
	var stone := stock.type_by_id(&"stone")
	stock.add(stone, BuildController.price_amount(nest.costs, stone))
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
	var outward := world.route_service.request_route(world.planner.accessible_entry(work_house), job_cell)
	var outward_energy := world.planner.travel_energy(outward.cost, worker.speed)
	worker.needs.satiety = outward_energy + 2.0
	test.expect(world.planner.plan_work(worker, work_house, worker.needs, worker.speed, worker.work_time, null) == null,
		"a worker without a canteen declines a job if she cannot bring the cargo home")
	worker.needs.eat()
	worker._decide()
	wanderer._decide()
	stranded._decide()
	test.expect(stranded.status == AntAgent.Status.WANDERING and stranded.motion.route == null, "isolated ant waits if there are no walkable neighbors")
	test.expect(worker._destination == &"work" and workplace.incoming_count() == 1 and worker._meal == null, "dry ant leaves its nest and immediately reserves a job slot without a meal")
	test.expect(wanderer._destination == &"wander" and wanderer.work.workplace == null, "idle ant leaves its nest to wander instead of choosing work across water")
	var cycles: Array[int] = [0]
	worker.work_completed.connect(func(_ant: Node2D, _job: Node2D): cycles[0] += 1)
	var loaded_return := world.planner.home_route(work_house, job_cell)
	var seconds_to_deliver := world.planner.travel_seconds(outward.cost, worker.speed) + worker.work.plan.work_seconds + world.planner.travel_seconds(loaded_return.cost, worker.speed * world.planner.carry_speed_ratio)
	var initial_steps := ceili(seconds_to_deliver * 30) + 4
	var reached_work := false
	for _step in range(initial_steps):
		for ant in [worker, wanderer, stranded]:
			ant._physics_process(1.0 / 30.0)
		reached_work = reached_work or (workplace.working_count() == 1 and worker.status == AntAgent.Status.WORKING)
	test.expect(reached_work, "dry ant reaches the workplace")
	test.expect(stock.quantity(wood) > start_wood, "dry worker carries the first batch to its local nest")
	test.expect(worker._destination == &"home", "workers can return home after unloading on an island with no canteen")
	test.expect(walked.size() >= 2 and wanderer.needs.satiety < wanderer.needs.capacity, "idle ant visits neighboring cells while losing satiety")
	test.expect(walked.all(func(cell: Vector2i) -> bool:
		return world.route_service.walkable(cell) and absi(cell.x - second_idle_nest.x) + absi(cell.y - second_idle_nest.y) <= 2), "wander stays on walkable cells near the nest")
	for step in range(ceili(world.match_controller.match_duration * 30) - initial_steps - 1):
		for ant in [worker, wanderer, stranded]:
			ant._physics_process(1.0 / 30.0)
	test.expect(cycles[0] > 1 and deaths == [AntAgent.DeathCause.STARVATION], "dry worker continues producing and delivering until starvation")
	test.expect(workplace.worker_count() == 0 and not work_house.residents.has(worker), "starvation releases the work slot and nest resident")
	test.expect(idle_deaths == [AntAgent.DeathCause.STARVATION, AntAgent.DeathCause.STARVATION], "both wandering and stationary ants without food starve before a standard match ends")
	test.expect(not idle_house.residents.has(wanderer) and not stranded_house.residents.has(stranded), "idle starvation removes residents from their nests")
	var successor := work_house.residents[0] as AntAgent
	successor._decide()
	_step_until(successor, func() -> bool: return successor.status == AntAgent.Status.WORKING)
	var food: ResourceType = stock.type_by_id(&"food")
	stock.add(food, 1)
	test.expect(successor.status == AntAgent.Status.WORKING and stock.available(food) == 1, "isolated workers leave global food unreserved")
	var canteen: BuildOption = preload("res://game/building/options/canteen.tres")
	if not world.build_controller.options.has(canteen):
		world.build_controller.unlock_option(canteen)
	var canteen_cell := job_cell + Vector2i.UP
	var royal := stock.type_by_id(&"royal")
	stock.add(royal, BuildController.price_amount(world.build_controller.price(canteen, canteen_cell), royal))
	test.expect(world.build_controller.try_build(canteen, canteen_cell), "new canteen restores access to food on the working island")
	successor._reconsider_route()
	test.expect(successor._destination == &"food" and successor._meal != null and workplace.worker_count() == 0, "worker switches to a reachable meal when a canteen opens")
	_step_until(successor, func() -> bool: return successor.status == AntAgent.Status.EATING)
	_step_until(successor, func() -> bool: return successor.status != AntAgent.Status.EATING)
	test.expect(stock.quantity(food) == 0 and successor.needs.satiety > 119.0, "restored meal replenishes the worker's satiety")
	_step_until(successor, func() -> bool: return successor.status == AntAgent.Status.WAITING_FOR_FOOD)
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
	world.build_controller.physical_construction = false
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
	job.output_per_second = 5.0
	test.expect(world.logistics.main_nest == main and not world.build_controller.demolition_check(main.cell).allowed(), "the first nest is the single protected construction center")
	var ant := depot.residents[0] as AntAgent
	ant.global_position = world.route_service.cell_to_world(job.cell)
	ant._decide()
	ant._physics_process(0.05)
	var before: int = stock.quantity(wood)
	ant._physics_process(ant.work_time)
	test.expect(WorldInventory.cargo_size(ant.transport.cargo) == ant.carry_capacity and stock.quantity(wood) == before and job.worker_count() == 0, "production loads only what the ant can carry and credits nothing before delivery")
	_step_until(ant, func() -> bool: return ant.transport.cargo.is_empty())
	test.expect(stock.depot_quantity(depot, wood) == 2 and stock.main_quantity(wood) == before and stock.quantity(wood) == before + 2, "a worker delivers production to its own nest")
	var central_price: Array[ResourceAmount] = [test.entry(wood, before + 1)]
	test.expect(stock.can_afford_all(central_price) and not stock.can_afford_all(central_price, true), "barracks stock does not count toward the immediate construction budget")
	test.expect(stock.deposit(depot, [test.entry(stone, 1)]), "mixed resources occupy the same depot")
	ant.global_position = world.route_service.cell_to_world(job.cell)
	# Simulate a load left at the workplace before the transport race.
	job._produce(wood, ant.carry_capacity + 1, true)
	ant.transport.cargo = job.take_output(ant.carry_capacity)
	ant.transport.deliver()
	test.expect(ant.transport.delivery_nest == depot and stock.deposit(depot, [test.entry(stone, 2)]), "another delivery can fill the chosen depot while a worker is moving")
	test.expect(stock.depot_fill(depot) == 5 and not stock.deposit(depot, [test.entry(stone, 1)]) and not world.build_controller.demolition_check(depot.cell).allowed(), "a full depot rejects additional stock and cannot be demolished")
	_step_until(ant, func() -> bool: return ant.waiting_reason == WorkPlan.WaitReason.STORAGE_FULL)
	test.expect(ant.waiting_reason == WorkPlan.WaitReason.STORAGE_FULL and WorldInventory.cargo_size(ant.transport.cargo) == 2, "a worker holds cargo near home when its storage fills up")
	test.expect(stock.main_quantity(wood) == before and stock.depot_fill(other) == 0, "a worker never unloads at another nest")
	test.expect(stock.pay_at(depot, [test.entry(stone, 2)]), "spending from the worker's home makes room")
	_step_until(ant, func() -> bool: return ant.transport.cargo.is_empty())
	test.expect(stock.depot_quantity(depot, wood) == 4, "held cargo reaches home after storage frees up")
	# Leave two surplus wood for the order, and isolate it from other resource orders.
	stock.pay_at(depot, [test.entry(wood, 2), test.entry(stone, 1)])
	var courier := main.residents.back() as AntAgent
	test.expect(courier.role == AntAgent.Role.CARRIER and courier.speed > ant.speed and courier.carry_capacity > ant.carry_capacity, "main nest spawns a faster carrier with a larger load")
	test.expect(world.planner.plan_work(courier, main, courier.needs, courier.speed, courier.work_time, courier._meal) == null and not job.reserve_worker(courier), "a carrier cannot get a production assignment or take a worker slot")
	# Orders replace automatic dispatch: the main nest wants exactly 2 wood (max = stock + 2), the depot holds 2 surplus.
	var wood_now: int = stock.nest_quantity(main, main, wood)
	main.set_order(str(wood.id), "min", wood_now + 1)
	main.set_order(str(wood.id), "max", wood_now + 2)
	var total: int = stock.quantity(wood)
	var main_before: int = stock.main_quantity(wood)
	courier._decide()
	test.expect(courier._destination == &"pickup" and courier.transport.pickup_source == depot and courier.transport.cargo.is_empty(), "an order sends the main carrier to the depot that has surplus before loading")
	_step_until(courier, func() -> bool: return courier.transport.shipment)
	test.expect(courier.transport.shipment and courier.transport.order_target == main and WorldInventory.cargo_size(courier.transport.cargo) == 2, "the carrier loads exactly what the target needs")
	test.expect(stock.quantity(wood) == total and stock.main_quantity(wood) == main_before and stock.depot_quantity(depot, wood) == 0, "dispatched cargo counts in totals during transport but cannot be spent centrally")
	_step_until(courier, func() -> bool: return courier.transport.cargo.is_empty())
	test.expect(stock.quantity(wood) == total and stock.main_quantity(wood) == main_before + 2, "shipment arrival moves stock without counting it twice")
	test.expect(world.logistics.order_surplus(depot, wood) == 0 and main.incoming.get(str(wood.id), 0) == 0, "an emptied depot has no surplus and the delivered batch no longer counts as incoming")
	var walked: Array[Vector2i] = []
	courier.cell_changed.connect(func(_old: Vector2i, next: Vector2i): walked.append(next))
	var satiety_before: float = courier.needs.satiety
	courier._decide()
	var visited_workplace := false
	for step in range(600):
		courier._physics_process(1.0 / 60.0)
		visited_workplace = visited_workplace or courier.transport.pickup_source is Workplace or courier._destination == &"work" or courier.status == AntAgent.Status.WORKING
	test.expect(not visited_workplace and courier.transport.cargo.is_empty() and job.pending_output_amount() == 1 and job.worker_count() == 0, "an idle carrier ignores workplace surplus and never attempts production")
	test.expect(walked.size() >= 2 and courier.needs.satiety < satiety_before, "a fed idle carrier leaves the nest and loses satiety while wandering")
	test.expect(walked.all(func(cell: Vector2i) -> bool:
		return world.route_service.walkable(cell) and absi(cell.x - main.cell.x) + absi(cell.y - main.cell.y) <= 2), "carrier walks remain on nearby walkable cells")
	# Even a stale pickup target must not let a carrier collect from a workplace.
	courier.transport.pickup_source = job
	courier.transport.load_pickup()
	test.expect(courier.transport.cargo.is_empty() and job.pending_output_amount() == 1, "a carrier cannot load goods directly from a workplace")
	ant.global_position = world.route_service.cell_to_world(job.cell)
	ant.needs.eat()
	ant._decide()
	_step_until(ant, func() -> bool: return not ant.transport.cargo.is_empty())
	test.expect(WorldInventory.cargo_size(ant.transport.cargo) == 1 and job.pending_output_amount() == 0 and job.worker_count() == 0 and stock.quantity(wood) == total, "a worker collects remaining output before producing another batch")
	_step_until(ant, func() -> bool: return ant.transport.cargo.is_empty())
	test.expect(stock.quantity(wood) == total + 1 and stock.depot_quantity(depot, wood) == 1, "the worker delivers workshop surplus to its own depot")
	courier.global_position = world.route_service.cell_to_world(main.cell)
	courier.needs.satiety = 10.0
	courier._decide()
	test.expect(courier._destination == &"food", "a hungry idle carrier seeks a meal instead of wandering")
	_step_until(courier, func() -> bool: return courier.status == AntAgent.Status.EATING)
	_step_until(courier, func() -> bool: return courier.status != AntAgent.Status.EATING)
	test.expect(courier.needs.satiety > 119.0, "the wandering carrier can reach its meal and recover")
	var canteen: Building = world.registry.at(Vector2i(1, 1))
	canteen.demolish()
	canteen.free()
	courier.needs.satiety = 0.1
	courier._decide()
	_step_until(courier, func() -> bool: return courier.status == AntAgent.Status.DEAD)
	test.expect(courier.status == AntAgent.Status.DEAD and not main.residents.has(courier), "an idle carrier without accessible food still starves")
	world.free()

func test_multiple_bases(test: Node) -> void:
	var tiles: Array = []
	for x in range(16):
		for y in range(3):
			tiles.append([x, y, 3, 0, 0, 0])
	var world: World = LevelLayout.create_world({"version": LevelLayout.VERSION, "tiles": tiles,
		"objects": [[0, 1, "Home"], [6, 1, "Home"], [1, 1, "Food"]]})
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	var stock: WorldInventory = world.inventory
	var main: House = world.logistics.main_nest
	var barracks := world.registry.at(Vector2i(6, 1)) as House
	var wood: ResourceType = stock.type_by_id(&"wood")
	var royal: ResourceType = stock.type_by_id(&"royal")
	var base_option: BuildOption = load("res://game/building/options/base_nest.tres")
	test.expect(world.build_controller.options.has(base_option) and BuildController.price_amount(base_option.costs, royal) == 1, "the catalog offers a base nest for one configurable crown")
	test.expect(not world.build_controller.try_build(base_option, Vector2i(9, 1)), "a base nest cannot be built without crowns")
	stock.add(royal, 1)
	test.expect(world.build_controller.try_build(base_option, Vector2i(9, 1)) and stock.quantity(royal) == 0, "building another base spends its crown once")
	var base := world.registry.at(Vector2i(9, 1)) as House
	test.expect(base.is_main_nest and base.resident_limit() == 20 and base.residents.size() == 5, "a built base has twenty resident slots and the starter population")
	test.expect(not barracks.is_main_nest and barracks.resident_limit() == 5 and barracks.display_title() == "ui.storage.local", "a barracks keeps five resident slots and its own title")
	var base_tint: Color = (base.get_node("Sprite") as Sprite2D).modulate
	var barracks_tint: Color = (barracks.get_node("Sprite") as Sprite2D).modulate
	test.expect(base_tint.is_equal_approx(Color.WHITE) and barracks_tint.is_equal_approx(House.BARRACKS_TINT), "barracks have a different tint from base nests: %s / %s" % [base_tint, barracks_tint])
	test.expect(stock.can_deposit(base, WorldInventory.base_capacity()) and not stock.can_deposit(base, WorldInventory.base_capacity() + 1) and stock.can_deposit(barracks, barracks.storage_capacity) and not stock.can_deposit(barracks, barracks.storage_capacity + 1), "each base caps its store at base_capacity() while barracks keep their own limit")
	var initial: int = stock.quantity(wood)
	stock.deposit(barracks, [test.entry(wood, 8)])
	# Keep the main nest's wood in its own stock and isolate this wood order.
	main.set_order(str(wood.id), "min", initial)
	for type in stock.registered_types():
		if type != wood: base.set_order(str(type.id), "min", 0)
	# The base wants 10 wood (max 10); the barracks surplus supplies one full carrier load of 6.
	base.set_order(str(wood.id), "min", 10)
	base.set_order(str(wood.id), "max", 10)
	var courier := main.residents.back() as AntAgent
	courier._decide()
	test.expect(courier.transport.pickup_source == barracks, "the carrier selects the barracks surplus")
	_step_until(courier, func() -> bool: return courier.transport.shipment)
	test.expect(courier.transport.order_target == base and WorldInventory.cargo_size(courier.transport.cargo) == 6, "an order carries a full carrier load from the barracks surplus to the base that is short")
	test.expect(stock.quantity(wood) == initial + 8 and stock.nest_quantity(base, main, wood) == 0 and base.incoming.get(str(wood.id), 0) == 6, "units en route count as incoming without appearing in the base")
	_step_until(courier, func() -> bool: return courier.transport.cargo.is_empty())
	test.expect(stock.nest_quantity(base, main, wood) == 6 and stock.nest_quantity(main, main, wood) == initial and base.incoming.get(str(wood.id), 0) == 0, "base windows show separate stock and arrival clears the incoming count")
	test.expect(stock.quantity(wood) == initial + 8 and stock.depot_quantity(barracks, wood) == 2, "delivery leaves the unshipped stock at the source")
	var house_option: SceneBuildOption = load("res://game/building/options/barracks.tres")
	var destination_cell := Vector2i(13, 1)
	test.expect(world.build_controller.try_build(house_option, destination_cell), "redirect fixture builds an empty destination")
	var destination := world.registry.at(destination_cell) as House
	# Suspend standing orders so the new request is the only demand for these two units.
	main.set_order(str(wood.id), "min", stock.nest_quantity(main, main, wood))
	base.set_order(str(wood.id), "min", stock.nest_quantity(base, main, wood))
	destination.request(str(wood.id), 2)
	courier._decide()
	_step_until(courier, func() -> bool: return courier.transport.shipment)
	test.expect(courier.transport.order_target == destination, "the one-time request claims the remaining two wood")
	var before_redirect: int = stock.quantity(wood)
	var base_before_redirect: int = stock.depot_quantity(base, wood)
	test.expect(world.build_controller.demolish_at(destination_cell), "an empty destination can be removed before delivery")
	courier.global_position = world.route_service.cell_to_world(world.planner.accessible_entry(base))
	courier.transport.deliver()
	test.expect(courier.transport.delivery_nest == base, "a removed destination reroutes the shipment to the closest available store")
	_step_until(courier, func() -> bool: return courier.transport.cargo.is_empty())
	test.expect(stock.quantity(wood) == before_redirect and stock.depot_quantity(base, wood) == base_before_redirect + 2 and stock.depot_fill(barracks) == 0, "redirected cargo arrives without loss or duplication")
	world.free()
	# Explicit base types survive editor save/load and register before legacy barracks.
	var layout := {"version": LevelLayout.VERSION, "tiles": tiles,
		"objects": [[6, 1, "Home"], [9, 1, "build/base_nest"], [0, 1, "build/base_nest"]]}
	world = LevelLayout.create_world(layout)
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	test.expect(world.logistics.main_nest.cell == Vector2i(9, 1) and not (world.registry.at(Vector2i(6, 1)) as House).is_main_nest, "an explicit base registers before barracks even if listed later in a map")
	var buildings: Array[Node] = []
	for building in world.registry.all():
		buildings.append(building)
	var captured: Dictionary = LevelLayout.capture(world.get_node("Map"), buildings)
	world.free()
	world = LevelLayout.create_world(captured)
	test.expect(world != null and LevelValidator.validate_world(world, "base round trip").is_empty(), "saved maps restore base and barracks definitions without validation errors")
	if world != null:
		var restored: Array[Building] = []
		world._collect_buildings(world, restored)
		test.expect(restored.filter(func(building: Building) -> bool: return building is House and building.is_main_nest).size() == 2, "both base nests retain their type through map save/load")
		world.free()

func test_orders(test: Node) -> void:
	var tiles: Array = []
	for x in range(16):
		for y in range(3):
			tiles.append([x, y, 3, 0, 0, 0])
	var world: World = LevelLayout.create_world({"version": LevelLayout.VERSION, "tiles": tiles,
		"objects": [[0, 1, "Home"], [6, 1, "Home"], [1, 1, "Food"]]})
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	var stock: WorldInventory = world.inventory
	var main: House = world.logistics.main_nest
	var barracks := world.registry.at(Vector2i(6, 1)) as House
	var wood: ResourceType = stock.type_by_id(&"wood")
	var key: String = str(wood.id)
	var have: int = stock.nest_quantity(main, main, wood)
	var defaults: NestDefaults = NestDefaults.load_defaults()
	test.expect(main.order_of(key).min == defaults.base_min and main.order_of(key).max == roundi(defaults.base_capacity / 3.0)
		and barracks.order_of(key).max == roundi(barracks.storage_capacity / 3.0),
		"default maximums use one third of each warehouse's capacity")
	# Explicit orders so the checks do not depend on the starting values.
	main.set_order(key, "min", have + 5)
	main.set_order(key, "max", have + 10)
	test.expect(world.logistics.order_need(main, wood) == 10, "a nest below its minimum asks up to its maximum, never beyond it")
	main.set_order(key, "max", have)
	test.expect(main.order_of(key).min == have and world.logistics.order_need(main, wood) == 0, "lowering the maximum below the minimum lowers the minimum; a nest at its minimum requests nothing")
	main.request(key, 4)
	test.expect(world.logistics.order_need(main, wood) == 4, "a one-time request asks for exactly the requested units")
	main.fulfil(key, 4)
	test.expect(world.logistics.order_need(main, wood) == 0 and not main.requests.has(key), "a delivered one-time request is cleared")
	stock.deposit(barracks, [test.entry(wood, 8)])
	barracks.set_order(key, "min", 5)
	barracks.set_order(key, "max", 5)
	test.expect(world.logistics.order_surplus(barracks, wood) == 3, "a source gives away only what stays above its own minimum")
	main.request(key, 3)
	var origin := Vector2i(5, 1)
	var order := world.logistics.nearest_order(origin, 3, func(pickup_cost: float, delivery_cost: float, start: Vector2i, target: Vector2i) -> bool:
		return start == origin and target == main.cell and pickup_cost > 0.0 and delivery_cost > pickup_cost)
	test.expect(order != null and order.source == barracks and order.target == main and order.amount == 3 and order.pickup.cells.front() == origin and order.pickup.cells.back() == barracks.cell, "courier order scoring resolves both endpoints and creates the selected pickup route")
	main.request(key, 0)
	main.set_order(key, "max", have + 2)
	test.expect(world.logistics.order_need(main, wood) == 0 and world.logistics.transfer_amount(barracks, main, wood) == 2,
		"overflow can go to a warehouse between its minimum and maximum")
	main.incoming[key] = 1
	test.expect(world.logistics.transfer_amount(barracks, main, wood) == 1, "overflow counts incoming goods against the receiver's maximum")
	main.incoming.erase(key)
	main.set_order(key, "min", 0)
	main.set_order(key, "max", 0)
	barracks.set_order(key, "min", 8)
	barracks.request(key, -6)
	test.expect(world.logistics.order_need(barracks, wood) == 0 and world.logistics.transfer_amount(barracks, main, wood) == 0,
		"a one-time export still keeps the source minimum in stock")
	barracks.set_order(key, "min", 5)
	order = world.logistics.nearest_order(origin, 3, func(_a: float, _b: float, _c: Vector2i, _d: Vector2i) -> bool: return true)
	test.expect(order != null and order.source == barracks and order.target == main and order.amount == 3, "an export finds a warehouse with room without a positive receiving order")
	var worker := main.residents.back() as AntAgent
	worker.transport.pickup_source = barracks
	worker.transport.order_target = main
	worker.transport._order_type = wood
	barracks.set_order(key, "min", 6)
	worker.transport.load_pickup()
	test.expect(barracks.requests[key] == -4 and stock.stock_of(barracks, wood) == 6,
		"pickup can take a partial load and leaves the source at its minimum")
	worker.transport.delivery_nest = main
	worker.transport.unload()
	test.expect(stock.stock_of(null, wood) == have + 2 and worker.transport.cargo.is_empty(), "exported goods arrive through the existing shipment ledger")
	var settings := barracks.capture_storage_settings()
	barracks.request(key, 0)
	barracks.restore_storage_settings(settings)
	test.expect(barracks.requests[key] == -4, "negative requests survive saving storage settings")
	barracks.record_export(key, 4)
	test.expect(not barracks.requests.has(key), "completed exports clear at zero")
	world.free()

func test_canteen_delivery(test: Node) -> void:
	var world: World = test.make_world()
	var stock := world.inventory
	var food := stock.type_by_id(WorldInventory.FOOD_ID)
	var canteen := world.registry.canteens()[0]
	var default_maximum := roundi(canteen.food_capacity / 3.0)
	var default_minimum := mini(floori(canteen.food_capacity * canteen.refill_fraction) + 1, default_maximum)
	test.expect(canteen.food_maximum == default_maximum and canteen.food_minimum == default_minimum
		and canteen.food_needed(default_minimum - 1) == default_maximum - default_minimum + 1
		and canteen.food_needed(default_minimum) == 0, "canteen defaults use one third of capacity and keep the refill threshold within it")
	canteen.set_food_order("max", 4)
	canteen.set_food_order("min", 2)
	test.expect(canteen.food_needed(1) == 3 and canteen.food_needed(2) == 0, "canteen refill aims for max only when stock is below min")
	canteen.set_food_order("min", 0)
	test.expect(world.logistics.order_need(canteen, food) == 0 and world.logistics.order_need(canteen, food, true) == 4, "zero minimum stops refill requests while the canteen can still receive surplus up to its maximum")
	var requested := canteen.food_capacity + 2
	canteen.request_food(requested)
	test.expect(canteen.food_needed(canteen.food_capacity - 1) == 1, "a one-time food order is bounded by available storage")
	stock.add(food, canteen.food_capacity + NestDefaults.load_defaults().base_min)
	var total := stock.quantity(food)
	var carrier := world.population.agents().back() as AntAgent
	carrier._decide()
	_step_until(carrier, func() -> bool: return carrier.transport.shipment)
	var load_size := canteen.incoming_food
	test.expect(load_size > 0 and stock.depot_quantity(canteen, food) == 0 and stock.quantity(food) == total, "a canteen refill travels before becoming local stock")
	test.expect(canteen.requested_food == requested and world.logistics.order_need(canteen, food) == canteen.food_capacity - load_size, "incoming food reserves storage without completing the request")
	_step_until(carrier, func() -> bool: return not carrier.transport.shipment)
	test.expect(stock.depot_quantity(canteen, food) == load_size and canteen.incoming_food == 0 and stock.quantity(food) == total, "unloading moves food without creating extra stock")
	test.expect(canteen.requested_food == requested - load_size, "only an actual canteen delivery reduces the remaining request")
	var feedback := canteen.stock_transfer_feedback
	test.expect(feedback.get_child_count() == 1 and feedback.get_child(0).get_node("Content/Amount").text == "+%d" % load_size, "canteens show the delivered quantity")
	var main_food := stock.stock_of(null, food)
	var worker := world.population.agents()[0]
	worker._seek_food()
	_step_until(worker, func() -> bool: return stock.quantity(food) < total)
	test.expect(stock.depot_quantity(canteen, food) == load_size - 1 and stock.stock_of(null, food) == main_food, "eating consumes local food first")
	test.expect(feedback.get_child_count() == 2 and feedback.get_child(1).get_node("Content/Amount").text == "−1", "a successful meal shows the consumed portion")
	stock.consume(stock.reserve(food, load_size - 1), canteen)
	worker._meal = stock.reserve(food, 2)
	worker._seek_food()
	total = stock.quantity(food)
	_step_until(worker, func() -> bool: return stock.quantity(food) < total)
	test.expect(stock.stock_of(null, food) == main_food - 2 and feedback.get_child_count() == 3 and feedback.get_child(2).get_node("Content/Amount").text == "−2", "an empty canteen uses colony stock and shows the full meal cost")
	canteen.restore_delivery_settings({})
	test.expect(canteen.food_minimum == default_minimum and canteen.food_maximum == default_maximum and canteen.requested_food == 0, "older saves use the current authored canteen defaults")
	world.free()

func test_authored_map(test: Node) -> void:
	var data: Dictionary = LevelStore.load_level("builtin/tidal_shards")
	test.expect(LevelValidator.validate("res://game/worlds/maps/tidal_shards.tres").is_empty(), "bundled maps support the same editor and command-line validator as scenes")
	test.expect(data.title == "Осколки прилива" and LevelStore.saved_levels().any(func(item: Dictionary) -> bool: return item.file == "builtin/tidal_shards"), "the authored archipelago is bundled and listed without a user save")
	var copy: Dictionary = LevelStore.load_level("builtin/tidal_shards")
	copy.tiles[0][0] = -100
	test.expect(LevelStore.load_level("builtin/tidal_shards").tiles[0][0] == 0, "editing a bundled map cannot mutate its shipped resource")
	var world: World = LevelLayout.create_world(data)
	test.expect(world != null and LevelValidator.validate_world(world, "tidal shards").is_empty(), "the new authored level passes offline validation")
	if world == null:
		return
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	var grid: TileGrid = world.route_service.snapshot()
	test.expect(world.map_size == Vector2i(136, 84) and grid.component_count() >= 6 and grid.node_count() < 3000, "the large map has separate island graphs and stores only its land nodes")
	test.expect(world.population.count() == 5 and world.logistics.main_nest.cell == Vector2i(68, 44), "the archipelago starts with one populated central base")
	var resources := {&"wood": 0, &"stone": 0, &"food": 0}
	var dry := 0
	var worker := world.population.agents()[0]
	for workplace in world.registry.workplaces():
		resources[workplace.output.id] += 1
		if not world.planner.food_within_range(workplace.cell, worker.speed, worker.needs.capacity): dry += 1
	test.expect(resources[&"wood"] >= 10 and resources[&"stone"] >= 10 and resources[&"food"] >= 8 and dry > 0, "distinct islands offer all resource types and optional frontiers needing a canteen")
	world.free()
	var idle: Dictionary = await _play_authored_map(test, false)
	var developed: Dictionary = await _play_authored_map(test, true)
	test.metrics["tidal_shards"] = {"idle": idle, "developed": developed}
	test.expect(developed.tasks > idle.tasks and developed.cycles > idle.cycles, "roads and production camps improve progression over an unchanged colony")
	test.expect(developed.deaths == 0 and developed.tasks >= 5, "the development route completes a stage without starvation")

func _play_authored_map(test: Node, develop: bool) -> Dictionary:
	seed(20261107)
	var world: World = LevelLayout.create_world(LevelStore.load_level("builtin/tidal_shards"))
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	var road: BuildOption = load("res://game/building/options/road.tres")
	var camp: BuildOption = load("res://game/building/options/barracks.tres")
	var timber_camp := Vector2i(60, 43)
	var quarry_camp := Vector2i(78, 47)
	var timber_camp_built := false
	if develop:
		if world.build_controller.try_build(camp, quarry_camp):
			(world.registry.at(quarry_camp) as House).set_order("stone", "max", 0)
		else:
			test.expect(false, "the starter budget funds a camp beside the larger quarry")
		for x in range(71, 79):
			world.build_controller.try_build(road, Vector2i(x, 44))
		for y in range(45, 48):
			world.build_controller.try_build(road, Vector2i(78, y))
		world.build_controller.try_build(road, Vector2i(68, 45))
		world.build_controller.try_build(road, Vector2i(68, 46))
	var deaths: Array[int] = [0]
	var cycles: Array[int] = [0]
	world.population.spawned.connect(func(ant: AntAgent):
		ant.died.connect(func(_ant: Node2D, _cause: int): deaths[0] += 1)
		ant.work_completed.connect(func(_ant: Node2D, _site: Node2D): cycles[0] += 1))
	for ant in world.population.agents():
		ant.died.connect(func(_ant: Node2D, _cause: int): deaths[0] += 1)
		ant.work_completed.connect(func(_ant: Node2D, _site: Node2D): cycles[0] += 1)
	world.match_controller.start(world.inventory)
	for tick in range(60 * 240):
		for ant in world.population.agents(): ant._physics_process(1.0 / 60.0)
		world.match_controller._process(1.0 / 60.0)
		if world.match_controller.is_finished(): break
		if tick % 60 == 0:
			if develop and not timber_camp_built:
				timber_camp_built = world.build_controller.try_build(camp, timber_camp)
				if timber_camp_built:
					(world.registry.at(timber_camp) as House).set_order("wood", "max", 0)
			if world.tasks.pending_reward:
				world.tasks.choose_reward(0)
			# Save the quarry's first deliveries for the timber camp before spending on orders.
			if not develop or timber_camp_built:
				_place_authored_request(world)
			if develop:
				var farm: BuildOption = load("res://game/building/options/farm.tres")
				if world.inventory.available(world.inventory.type_by_id(&"food")) >= 10 and world.build_controller.can_build(farm, Vector2i(68, 46)):
					world.build_controller.try_build(farm, Vector2i(68, 46))
			await test.get_tree().process_frame
	var result := {"tasks": world.tasks.completed_count, "level": world.tasks.level, "cycles": cycles[0], "deaths": deaths[0], "ants": world.population.count(), "time_left": snappedf(world.match_controller.time_remaining, 0.1)}
	if develop:
		test.expect(timber_camp_built and world.population.count() == 15, "stone shipments pay for a second production camp")
	world.free()
	return result

func _place_authored_request(world: World) -> void:
	for task in world.tasks.slots:
		if task == null: continue
		for variant in task.variants:
			var order := world.tasks.start_order(task.id, variant.id)
			if order == null: continue
			# Feast orders share the meal supply with the workers.
			if not world.inventory.can_afford_all(world.build_controller.price(variant.building), true):
				continue
			for y in range(40, 49):
				for x in range(62, 78):
					if world.build_controller.try_build(variant.building, Vector2i(x, y), order):
						return

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
	stock.pay_at(null, [test.entry(food, stock.nest_quantity(main, main, food))])
	var before: int = stock.quantity(food)
	test.expect(not population.recruit(main, AntAgent.Role.WORKER) and stock.quantity(food) == before and main.residents.size() == 5, "unaffordable recruitment leaves residents and stock intact")
	stock.add(food, 300)
	var nested_recruits: Array[bool] = []
	population.spawned.connect(func(_ant: AntAgent):
		nested_recruits.append(population.recruit(main, AntAgent.Role.CARRIER)))
	for index in range(15):
		var role: AntAgent.Role = AntAgent.Role.WORKER if index % 2 == 0 else AntAgent.Role.CARRIER
		before = stock.quantity(food)
		var price: int = BuildController.price_amount(world.population.recruitment.price(role), food)
		test.expect(population.recruit(main, role) and stock.quantity(food) == before - price, "each recruit is spawned after exactly one price payment")
	test.expect(main.residents.size() == 20 and nested_recruits.size() == 15 and not nested_recruits.has(true), "reentrant requests cannot exceed the twenty-resident limit")
	before = stock.quantity(food)
	test.expect(not population.recruit(main, AntAgent.Role.WORKER) and stock.quantity(food) == before, "a full main nest rejects a purchase without spending")
	var dead := main.residents[0] as AntAgent
	dead._decide()
	var job: Workplace = dead.work.workplace
	var ticket: StockReservation = dead._meal
	var death_causes: Array[int] = []
	dead.died.connect(func(_ant: Node2D, cause: int): death_causes.append(cause))
	before = stock.quantity(food)
	test.expect(population.kill_resident(main, AntAgent.Role.WORKER) and death_causes == [AntAgent.DeathCause.PLAYER], "player can kill one assigned worker")
	test.expect(main.residents.size() == 19 and not ticket.active and job != null and not job.has_worker(dead) and stock.quantity(food) == before, "killing releases the resident slot, work slot, and food reservation without a refund")
	test.expect(population.recruit(main, AntAgent.Role.CARRIER) and main.residents.size() == 20, "a killed resident frees one slot for recruitment")
	var recruited := main.residents.back() as AntAgent
	test.expect(recruited.home == main and recruited.role == AntAgent.Role.CARRIER and recruited.speed == 36.0 and recruited.carry_capacity == 6, "recruited carriers belong to the selected nest and retain their role parameters")
	var nest: BuildOption = load("res://game/building/options/barracks.tres")
	test.expect(world.build_controller.try_build(nest, Vector2i(30, 29)), "recruitment fixture creates a small nest")
	var local := world.registry.at(Vector2i(30, 29)) as House
	test.expect(local.resident_limit() == 5 and not population.recruit(local, AntAgent.Role.WORKER), "small nests preserve their five-resident capacity")
	var wood: ResourceType = stock.type_by_id(&"wood")
	stock.deposit(local, [test.entry(wood, 6)])
	var carrier: AntAgent
	for resident: AntAgent in main.residents:
		if resident.role == AntAgent.Role.CARRIER:
			carrier = resident
			break
	# Main needs 6 wood (max = stock + 6); the barracks surplus covers a full carrier load.
	var main_wood: int = stock.nest_quantity(main, main, wood)
	main.set_order(str(wood.id), "min", main_wood + 1)
	main.set_order(str(wood.id), "max", main_wood + 6)
	# Keep food at home in this fixture so the only shipment is the wood under test.
	main.set_order(str(food.id), "min", stock.stock_of(null, food))
	carrier._decide()
	_step_until(carrier, func() -> bool: return carrier.transport.shipment)
	var total: int = stock.quantity(wood)
	test.expect(carrier.transport.shipment and population.kill_resident(main, AntAgent.Role.CARRIER), "a carrier can be killed while hauling a shipment")
	test.expect(stock.quantity(wood) == total - 6 and not main.residents.has(carrier), "killing a carrier removes its cargo from totals exactly once")
	test.expect(population.kill_resident(local, AntAgent.Role.CARRIER) and not population.kill_resident(local, AntAgent.Role.CARRIER), "empty role removal fails without affecting another nest")
	world.free()
