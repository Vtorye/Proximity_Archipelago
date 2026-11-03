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
	var worked_near_death := false
	for step in range(30 * 12):
		for ant in [worker, wanderer, stranded]:
			ant._physics_process(1.0 / 30.0)
		if step == 90:
			test.expect(workplace.working_count() == 1 and worker.status == AntAgent.Status.WORKING, "dry ant reaches the workplace")
		if worker.needs.satiety < 1.0 and worker.status == AntAgent.Status.WORKING:
			worked_near_death = true
	test.expect(stock.quantity(wood) > start_wood + workplace.output_amount, "dry worker completes successive production cycles")
	test.expect(walked.size() >= 2 and wanderer.needs.satiety < AntNeeds.CAPACITY, "idle ant visits neighboring cells while losing satiety")
	test.expect(walked.all(func(cell: Vector2i) -> bool:
		return world.route_service.walkable(cell) and absi(cell.x - second_idle_nest.x) + absi(cell.y - second_idle_nest.y) <= 2), "wander stays on walkable cells near the nest")
	for step in range(30 * (ceili(world.match_controller.match_duration) - 12) - 1):
		for ant in [worker, wanderer, stranded]:
			ant._physics_process(1.0 / 30.0)
		if worker.needs.satiety < 1.0 and worker.status == AntAgent.Status.WORKING:
			worked_near_death = true
	test.expect(worked_near_death and deaths == [AntAgent.DeathCause.STARVATION], "dry worker stays on the job until starvation")
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
