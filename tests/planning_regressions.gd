extends RefCounted
## Reproductions of nearby resource selection and live construction while ants are moving.

func run(test: Node) -> void:
	await _nearby_resources(test)
	await _stock_independent(test)
	await _load_scoring(test)
	await _slot_race(test)
	await _workload_ui(test)
	await _new_workplace(test)
	await _road_updates(test)
	await _returning_cargo(test)
	await _coalesced_updates(test)
	await _active_work(test)
	await _hungry_retarget(test)

func _nearby_resources(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	for sample in [[Vector2i(46, 48), &"wood"], [Vector2i(54, 47), &"stone"]]:
		ant.global_position = world.route_service.cell_to_world(sample[0])
		var plan: WorkPlan = world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
		test.expect(plan != null and plan.workplace != null and plan.workplace.output.id == sample[1], "nearby needed wood and stone beat a more distant berry bush")
		if plan != null and plan.workplace != null: plan.workplace.release_worker(ant)
	world.free()
	await test.get_tree().process_frame

func _stone_only(world: World, ant: AntAgent) -> Workplace:
	var stone: Workplace = world.get_node("Workplace2") as Workplace
	for workplace in world.registry.workplaces(): workplace.work_slots = 0
	stone.work_slots = 4
	ant._decide()
	return stone

func _new_workplace(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	var stone: Workplace = _stone_only(world, ant)
	test.expect(ant.current_workplace == stone, "reproduction starts with an ant heading for distant stone")
	for step in range(30): ant._physics_process(1.0 / 60.0)
	var before_position: Vector2 = ant.global_position
	test.expect(before_position != ant.home.global_position, "retarget fixture is already moving between cell centers")
	var ticket: StockReservation = ant._meal
	var berry: BuildOption = load("res://game/building/options/apple_tree.tres")
	test.expect(world.build_controller.try_build(berry, Vector2i(50, 49)), "nearby berry bush is built through the normal command")
	await test.get_tree().process_frame
	var nearby: Workplace = world.registry.at(Vector2i(50, 49)) as Workplace
	test.expect(ant.current_workplace == nearby and ant._destination == &"work", "walking ant switches to a newly built nearer needed workplace")
	test.expect(not stone.workers.has(ant) and nearby.workers.has(ant), "retargeting transfers the work reservation")
	test.expect(ant._meal == ticket and ticket.active, "retargeting preserves the reserved meal")
	test.expect(ant.global_position == before_position, "retargeting never teleports a moving ant")
	test.expect(ant.motion.route.cells.back() == nearby.cell, "replacement route actually reaches the new workplace")
	world.free()
	await test.get_tree().process_frame

func _road_updates(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	var stone: Workplace = _stone_only(world, ant)
	var road: BuildOption = load("res://game/building/options/road.tres")
	var off_route := Vector2i(49, 49)
	if ant.motion.route.cells.has(off_route): off_route = Vector2i(50, 50)
	test.expect(not ant.motion.route.cells.has(off_route), "shortcut fixture is outside the old route")
	test.expect(world.build_controller.try_build(road, off_route), "off-route shortcut can be constructed")
	await test.get_tree().process_frame
	test.expect(ant.motion.route.cells.has(off_route) and ant.motion.route.revision == world.route_service.revision, "walking ant adopts a cheaper route even when the old path remains valid")
	test.expect(ant.current_workplace == stone and ant._destination == &"work", "new road does not turn a healthy worker toward the canteen")
	var on_route: Vector2i = ant.motion.route.cells[2]
	test.expect(world.build_controller.try_build(road, on_route), "road can also improve the active route")
	await test.get_tree().process_frame
	test.expect(ant.current_workplace == stone and stone.workers.has(ant) and ant._destination == &"work", "improving an active route preserves its job and slot")
	world.free()
	await test.get_tree().process_frame

func _returning_cargo(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	ant.global_position = world.route_service.cell_to_world(Vector2i(52, 49))
	ant._carrying = true
	ant._go_home()
	var berry: BuildOption = load("res://game/building/options/apple_tree.tres")
	test.expect(world.build_controller.try_build(berry, Vector2i(52, 48)), "new workplace can appear beside a loaded returning ant")
	await test.get_tree().process_frame
	test.expect(ant._destination == &"home" and ant._carrying and ant.current_workplace == null, "new work does not interrupt delivery of an existing load")
	var next_cell: Vector2i = ant.motion.route.cells[1]
	test.expect(world.build_controller.try_build(load("res://game/building/options/road.tres"), next_cell), "return route can be improved while loaded")
	await test.get_tree().process_frame
	test.expect(ant._destination == &"home" and ant._carrying and ant.motion.route.cells.back() == ant.home.cell, "road update keeps the load heading home")
	world.free()
	await test.get_tree().process_frame

func _coalesced_updates(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	var stone: Workplace = _stone_only(world, ant)
	var searches: int = world.route_service.search_count
	var road: BuildOption = load("res://game/building/options/road.tres")
	for cell in [Vector2i(49, 49), Vector2i(50, 49), Vector2i(51, 49)]:
		test.expect(world.build_controller.try_build(road, cell), "several road edits can be committed in the same frame")
	await test.get_tree().process_frame
	test.expect(world.route_service.search_count - searches <= 3, "one frame of edits shares a single home outward and food refresh")
	test.expect(ant.current_workplace == stone and ant.motion.route.revision == world.route_service.revision, "coalesced reconsideration uses the final navigation snapshot")
	world.free()
	await test.get_tree().process_frame

func _active_work(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	var stone: Workplace = _stone_only(world, ant)
	ant.global_position = stone.global_position
	ant._arrive()
	test.expect(ant.status == AntAgent.Status.WORKING, "work cycle fixture has already reached its workplace")
	test.expect(world.build_controller.try_build(load("res://game/building/options/apple_tree.tres"), Vector2i(54, 45)), "nearer alternative may appear during a work cycle")
	await test.get_tree().process_frame
	test.expect(ant.status == AntAgent.Status.WORKING and ant.current_workplace == stone and stone.workers.has(ant), "new alternatives do not discard a work cycle already in progress")
	world.free()
	await test.get_tree().process_frame

func _hungry_retarget(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	_stone_only(world, ant)
	for step in range(30): ant._physics_process(1.0 / 60.0)
	var cell: Vector2i = world.route_service.world_to_cell(ant.global_position)
	ant.needs.satiety = world.planner.escape_energy(cell, ant.speed) + AntNeeds.SAFETY_MARGIN + 1.0
	test.expect(world.build_controller.try_build(load("res://game/building/options/apple_tree.tres"), Vector2i(50, 49)), "new nearby work can appear beside a hungry walking ant")
	await test.get_tree().process_frame
	test.expect(ant._destination == &"food" and ant.current_workplace == null and ant._meal.active, "hungry ant rejects even nearer work and keeps its meal reservation")
	test.expect(ant.needs.can_afford(world.planner.escape_energy(cell, ant.speed)), "hungry retarget retains enough energy to reach food safely")
	world.free()
	await test.get_tree().process_frame

func _stock_independent(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	ant.global_position = world.route_service.cell_to_world(Vector2i(46, 48))
	var before: WorkPlan = world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	var chosen: Workplace = before.workplace
	chosen.release_worker(ant)
	world.inventory.add(world.inventory.type_by_id(&"wood"), 1000)
	world.inventory.add(world.inventory.type_by_id(&"stone"), 1000)
	var food: ResourceType = world.inventory.type_by_id(&"food")
	world.inventory.try_spend(test.entry(food, world.inventory.available(food)))
	var after: WorkPlan = world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	test.expect(after.workplace == chosen and after.workplace.output.id == &"wood", "large material stocks and minimal free food do not change a safe work choice")
	after.workplace.release_worker(ant)
	world.free()
	await test.get_tree().process_frame

func _place(world: World, cell: Vector2i) -> Workplace:
	var workplace := Workplace.new()
	workplace.work_slots = 4
	workplace.output = world.inventory.type_by_id(&"wood")
	workplace.position = world.route_service.cell_to_world(cell)
	workplace.setup(cell, null)
	world.buildings.add_child(workplace)
	world.registry.register(workplace)
	return workplace

func _reserve_walk(world: World, workplace: Workplace, ant: AntAgent) -> void:
	workplace.reserve_worker(ant)
	ant.current_workplace = workplace
	ant._walk(world.route_service.request_route(ant.home.cell, workplace.cell), &"work")

func _load_scoring(test: Node) -> void:
	var world: World = test.make_world()
	for workplace in world.registry.workplaces(): workplace.free()
	var near: Workplace = _place(world, Vector2i(48, 50))
	var far: Workplace = _place(world, Vector2i(50, 50))
	var ants: Array[AntAgent] = world.population.agents()
	_reserve_walk(world, near, ants[1])
	var plan: WorkPlan = world.planner.plan_work(ants[0], ants[0].home, ants[0].needs, ants[0].speed, ants[0].work_time, ants[0]._meal)
	test.expect(plan.workplace == far, "equal travel time prefers fewer working or incoming ants")
	plan.workplace.release_worker(ants[0])
	far.free()
	far = _place(world, Vector2i(51, 50))
	_reserve_walk(world, near, ants[2])
	plan = world.planner.plan_work(ants[0], ants[0].home, ants[0].needs, ants[0].speed, ants[0].work_time, ants[0]._meal)
	test.expect(plan.workplace == near, "two incoming ants add exactly one second and still beat the longer trip")
	plan.workplace.release_worker(ants[0])
	_reserve_walk(world, near, ants[3])
	plan = world.planner.plan_work(ants[0], ants[0].home, ants[0].needs, ants[0].speed, ants[0].work_time, ants[0]._meal)
	test.expect(plan.workplace == far, "three incoming ants add 1.5 seconds and make the farther workplace preferable")
	plan.workplace.release_worker(ants[0])
	world.free()
	await test.get_tree().process_frame

func _slot_race(test: Node) -> void:
	var world: World = test.make_world()
	for workplace in world.registry.workplaces(): workplace.work_slots = 0
	var workplace: Workplace = world.get_node("Workplace") as Workplace
	workplace.work_slots = 1
	var ants: Array[AntAgent] = world.population.agents()
	var first: WorkPlan = world.planner.plan_work(ants[0], ants[0].home, ants[0].needs, ants[0].speed, ants[0].work_time, ants[0]._meal)
	var second: WorkPlan = world.planner.plan_work(ants[1], ants[1].home, ants[1].needs, ants[1].speed, ants[1].work_time, ants[1]._meal)
	test.expect(first.workplace == workplace and second.waiting_for_slot and workplace.worker_count() == 1, "last work slot is reserved before arrival and cannot be claimed twice")
	workplace.release_worker(ants[0])
	world.free()
	await test.get_tree().process_frame

func _workload_ui(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	var workplace: Workplace = _stone_only(world, ant)
	var menu: BuildMenu = load("res://overlays/build_menu.tscn").instantiate() as BuildMenu
	var context := BuildMenuContext.new()
	context.controller = world.build_controller
	context.population = world.population
	context.art = world.art
	context.cell = workplace.cell
	context.anchor = Rect2(300, 150, 32, 32)
	menu.payload = context
	test.add_child(menu)
	test.expect(workplace.incoming_count() == 1 and workplace.working_count() == 0 and menu._description.text.contains("0+1/4"), "UI immediately includes a reserved walking worker")
	for step in range(1200):
		ant._physics_process(1.0 / 60.0)
		if ant.status == AntAgent.Status.WORKING: break
	test.expect(workplace.incoming_count() == 0 and workplace.working_count() == 1 and menu._description.text.contains("1+0/4"), "arrival transfers the same worker from incoming to working in the UI")
	ant._physics_process(ant.work_time + 0.01)
	test.expect(ant._carrying and ant._destination == &"home" and workplace.worker_count() == 0 and menu._description.text.contains("0+0/4"), "loaded return is excluded from the displayed enterprise load")
	menu.free()
	for place in world.registry.workplaces(): place.work_slots = 0
	var waiting_ant: AntAgent = world.population.agents()[1]
	var hud := MatchHud.new()
	hud.world = world
	test.add_child(hud)
	waiting_ant._decide()
	test.expect(waiting_ant.waiting_reason == WorkPlan.WaitReason.SLOTS_FULL and hud._waiting.text == "Ждут мест: 1" and hud._waiting.visible, "home waiting has a visible full-workplace explanation")
	hud.free()
	world.free()
	await test.get_tree().process_frame
