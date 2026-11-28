extends RefCounted
## Reproductions of nearby resource selection and live construction while ants are moving.

func run(test: Node) -> void:
	await _nearby_resources(test)
	await _stock_independent(test)
	await _load_scoring(test)
	await _slot_race(test)
	await _workload_ui(test)
	await _tile_inspector(test)
	await _new_workplace(test)
	await _road_updates(test)
	await _returning_cargo(test)
	await _coalesced_updates(test)
	await _active_work(test)
	await _hungry_retarget(test)
	await _replanning_progress(test)
	await _second_nest_meal_return(test)

func _second_nest_meal_return(test: Node) -> void:
	var tiles: Array = []
	var nest_cell := Vector2i(20, 1)
	var job_cell := nest_cell + Vector2i.RIGHT
	for x in range(job_cell.x + 2):
		for y in range(3):
			tiles.append([x, y, 3, 0, 0, 0])
	var world := LevelLayout.create_world({"version": LevelLayout.VERSION, "tiles": tiles,
		"objects": [[0, 1, "Home"], [1, 1, "Food"], [job_cell.x, job_cell.y, "Workplace"]]})
	world.auto_start = false
	world.build_controller.physical_construction = false
	world.task_deck = null
	test.add_child(world)
	var built := world.build_controller.try_build(load("res://game/colony/nests/barracks.tres"), nest_cell)
	test.expect(built, "a second nest can be built beside the remote workplace")
	if not built:
		world.free()
		return
	var nest := world.registry.at(nest_cell) as House
	var worker := nest.residents[0] as AntAgent
	var canteen := Vector2i(1, 1)
	var return_route := world.planner.home_route(nest, canteen)
	var escape := world.planner.escape_energy(nest_cell, worker.speed)
	var unloaded := world.planner.travel_energy(return_route.cost, worker.speed) + escape
	var loaded := world.planner.travel_energy(return_route.cost, worker.speed * world.planner.carry_speed_ratio) + escape
	test.expect(worker.needs.can_afford(unloaded) and not worker.needs.can_afford(loaded), "only the empty-handed return fits a full worker's energy budget")
	worker.needs.satiety = escape + worker.needs.safety_margin + 0.25
	worker._decide()
	test.expect(worker._destination == &"food", "the hungry worker leaves the new nest to eat")
	var cycles := [0]
	worker.work_completed.connect(func(_worker: Node2D, _place: Node2D): cycles[0] += 1)
	for frame in range(30 * 115):
		worker._physics_process(1.0 / 30.0)
		if cycles[0] > 0:
			break
	test.expect(cycles[0] > 0, "after eating, the empty-handed worker returns to the second nest and resumes production")
	world.free()
	await test.get_tree().process_frame

func _tile_inspector(test: Node) -> void:
	var world: World = test.make_world()
	var overlay := NavigationOverlay.new()
	overlay.world = world
	var panel := preload("res://game/navigation/ui/navigation_panel.tscn").instantiate() as NavigationPanel
	panel.overlay = overlay
	test.add_child(panel)
	var map := world.map as TerrainMap
	var dry_cell := Vector2i(24, 25)
	var wet_cell := Vector2i(25, 25)
	map.paint_tile(dry_cell, map.catalog.by_id(&"dry").tile, true)
	map.paint_tile(wet_cell, map.catalog.by_id(&"wet").tile, true)
	panel.inspect_cell(dry_cell)
	await test.get_tree().process_frame
	test.expect(panel.visible and panel._detail.get_parsed_text().contains(TranslationServer.translate("ui.terrain.build_price") % 50), "selecting dry ground displays its build rules and discount")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	panel._header._drag_input(press)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(-40, -20)
	panel._header._input(drag)
	press.pressed = false
	panel._header._input(press)
	var position := panel.position
	panel._header.toggle.pressed.emit()
	panel.inspect_cell(wet_cell)
	await test.get_tree().process_frame
	test.expect(panel._header.collapsed and panel.position == position, "a new tile keeps the moved inspector folded in place")
	panel._header.toggle.pressed.emit()
	test.expect(panel._detail.get_parsed_text().contains(TranslationServer.translate("ui.terrain.adjacency") % [25, 1]), "opening the inspector shows the newly selected tile's bonus")
	panel.free()
	overlay.free()
	world.free()
	await test.get_tree().process_frame

func _nearby_resources(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	for sample in [[Vector2i(21, 23), &"wood"], [Vector2i(29, 22), &"stone"]]:
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
	test.expect(ant.work.workplace == stone, "reproduction starts with an ant heading for distant stone")
	for step in range(30): ant._physics_process(1.0 / 60.0)
	var before_position: Vector2 = ant.global_position
	test.expect(before_position != ant.home.global_position, "retarget fixture is already moving between cell centers")
	var ticket: StockReservation = ant._meal
	test.expect(_plant_berry(world, Vector2i(25, 24)), "nearby berry bush is built through the normal command")
	await test.get_tree().process_frame
	var nearby: Workplace = world.registry.at(Vector2i(25, 24)) as Workplace
	test.expect(ant.work.workplace == nearby and ant._destination == &"work", "walking ant switches to a newly built nearer needed workplace")
	test.expect(not stone.workers.has(ant) and nearby.workers.has(ant), "retargeting transfers the work reservation")
	test.expect(ant._meal == ticket and ticket.active, "retargeting preserves the reserved meal")
	test.expect(ant.global_position == before_position, "retargeting never teleports a moving ant")
	if nearby != null:
		test.expect(ant.motion.route.cells.back() == nearby.cell, "replacement route actually reaches the new workplace")
	world.free()
	await test.get_tree().process_frame

func _road_updates(test: Node) -> void:
	var world: World = test.make_world()
	await test.get_tree().process_frame
	var ant: AntAgent = world.population.agents()[0]
	var stone: Workplace = _stone_only(world, ant)
	var walking_route := ant.motion.route
	var road: BuildOption = load("res://game/terrain/options/road.tres")
	var off_route := Vector2i(24, 24)
	if ant.motion.route.cells.has(off_route): off_route = Vector2i(25, 25)
	test.expect(not ant.motion.route.cells.has(off_route), "shortcut fixture is outside the old route")
	test.expect(world.build_controller.try_build(road, off_route), "off-route shortcut can be constructed")
	await test.get_tree().process_frame
	test.expect(ant.motion.route == walking_route, "an off-route shortcut keeps the current safe trip")
	var new_route := world.route_service.request_route(walking_route.cells.front(), walking_route.cells.back())
	test.expect(new_route.cells.has(off_route), "a fresh route uses the cheaper shortcut")
	test.expect(ant.work.workplace == stone and ant._destination == &"work", "new road does not turn a healthy worker toward the canteen")
	var on_route: Vector2i = ant.motion.route.cells[2]
	test.expect(world.build_controller.try_build(road, on_route), "road can also improve the active route")
	await test.get_tree().process_frame
	test.expect(ant.work.workplace == stone and stone.workers.has(ant) and ant._destination == &"work", "improving an active route preserves its job and slot")
	world.free()
	await test.get_tree().process_frame

func _returning_cargo(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	ant.global_position = world.route_service.cell_to_world(Vector2i(27, 24))
	ant.transport.carrying = true
	ant._go_home()
	test.expect(_plant_berry(world, Vector2i(27, 23)), "new workplace can appear beside a loaded returning ant")
	await test.get_tree().process_frame
	test.expect(ant._destination == &"home" and ant.transport.carrying and ant.work.workplace == null, "new work does not interrupt delivery of an existing load")
	var next_cell: Vector2i = ant.motion.route.cells[1]
	test.expect(world.build_controller.try_build(load("res://game/terrain/options/road.tres"), next_cell), "return route can be improved while loaded")
	await test.get_tree().process_frame
	test.expect(ant._destination == &"home" and ant.transport.carrying and ant.motion.route.cells.back() == ant.home.cell, "road update keeps the load heading home")
	world.free()
	await test.get_tree().process_frame

func _coalesced_updates(test: Node) -> void:
	var world: World = test.make_world()
	await test.get_tree().process_frame
	var ant: AntAgent = world.population.agents()[0]
	var stone: Workplace = _stone_only(world, ant)
	var routes := world.route_service
	var origin := world.planner.accessible_entry(ant.home)
	var departure := routes.distances_from(origin)
	var home := routes.reverse_field([origin])
	var searches: int = world.route_service.search_count
	var repairs: int = routes.field_repairs
	var active_route: Route = ant.motion.route
	var revision: int = world.route_service.revision
	var road: BuildOption = load("res://game/terrain/options/road.tres")
	var cells: Array[Vector2i] = []
	for cell in world.route_service.snapshot().walkable_cells():
		if world.route_service.entry_cost(cell) > 0.35 and world.build_controller.can_build(road, cell):
			cells.append(cell)
			if cells.size() == 3: break
	test.expect(cells.size() == 3, "fixture has three tiles that roads make cheaper")
	var map := world.map as TerrainMap
	var old_tile := map.key_at(cells.front())
	for cell in cells:
		test.expect(world.build_controller.try_build(road, cell), "several road edits can be committed in the same frame")
	await test.get_tree().process_frame
	test.expect(world.route_service.revision == revision + 3 and world.route_service.search_count == searches, "cheaper roads advance the revision without rebuilding fields immediately")
	test.expect(routes.field_repairs == repairs, "a batch of roads does not repair fields until read")
	test.expect(routes.distances_from(origin) == departure and routes.reverse_field([origin], home) == home
		and routes.field_repairs == repairs + 2 and routes.search_count == searches,
		"the next reads repair forward and reverse fields once for the complete batch")
	test.expect(ant.work.workplace == stone and ant.motion.route == active_route, "cheaper roads preserve an active safe path")
	var fresh := world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal, stone)
	test.expect(fresh != null and fresh.outward != null and fresh.outward.revision == world.route_service.revision, "the next departure uses the new road costs")
	map.paint_tile(cells.front(), old_tile, true)
	routes.update_cells([cells.front()], world.registry.blocked_cells())
	test.expect(routes.distances_from(origin) != departure and routes.reverse_field([origin], home) != home,
		"raising a tile cost invalidates complete fields in both directions")
	world.free()
	await test.get_tree().process_frame

func _active_work(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	var stone: Workplace = _stone_only(world, ant)
	ant.global_position = stone.global_position
	ant._arrive()
	test.expect(ant.status == AntAgent.Status.WORKING, "work cycle fixture has already reached its workplace")
	test.expect(_plant_berry(world, Vector2i(29, 20)), "nearer alternative may appear during a work cycle")
	await test.get_tree().process_frame
	test.expect(ant.status == AntAgent.Status.WORKING and ant.work.workplace == stone and stone.workers.has(ant), "new alternatives do not discard a work cycle already in progress")
	world.free()
	await test.get_tree().process_frame

func _hungry_retarget(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	_stone_only(world, ant)
	for step in range(30): ant._physics_process(1.0 / 60.0)
	var cell: Vector2i = world.route_service.world_to_cell(ant.global_position)
	ant.needs.satiety = world.planner.escape_energy(cell, ant.speed) + ant.needs.safety_margin + 1.0
	test.expect(_plant_berry(world, Vector2i(25, 24)), "new nearby work can appear beside a hungry walking ant")
	await test.get_tree().process_frame
	test.expect(ant._destination == &"food" and ant.work.workplace == null and ant._meal.active, "hungry ant rejects even nearer work and keeps its meal reservation")
	test.expect(ant.needs.can_afford(world.planner.escape_energy(cell, ant.speed)), "hungry retarget retains enough energy to reach food safely")
	world.free()
	await test.get_tree().process_frame

func _stock_independent(test: Node) -> void:
	var world: World = test.make_world()
	var ant: AntAgent = world.population.agents()[0]
	ant.global_position = world.route_service.cell_to_world(Vector2i(21, 23))
	var before: WorkPlan = world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	var chosen: Workplace = before.workplace if before != null else null
	test.expect(chosen != null, "the initial fixture has an affordable work plan")
	if chosen != null:
		chosen.release_worker(ant)
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	# Leave space for a complete load so storage backpressure cannot affect this comparison.
	var space: int = world.inventory.free_space(null) - ant.carry_capacity
	world.inventory.add(wood, space / 2)
	world.inventory.add(stone, space - space / 2)
	var food: ResourceType = world.inventory.type_by_id(&"food")
	world.inventory.try_spend(test.entry(food, world.inventory.available(food)))
	var after: WorkPlan = world.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal)
	var assigned: Workplace = after.workplace if after != null else null
	test.expect(chosen != null and assigned == chosen and assigned.output.id == &"wood", "large material stocks and minimal free food do not change a safe work choice")
	if assigned != null:
		assigned.release_worker(ant)
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

func _plant_berry(world: World, cell: Vector2i) -> bool:
	var berry: BuildOption = load("res://game/colony/workplaces/berry_bush.tres")
	for item in world.build_controller.price(berry, cell):
		var shortfall := item.amount - world.inventory.available(item.type)
		if shortfall > 0:
			world.inventory.add(item.type, shortfall)
	return world.build_controller.try_build(berry, cell)

func _reserve_walk(world: World, workplace: Workplace, ant: AntAgent) -> void:
	workplace.reserve_worker(ant)
	ant.work.workplace = workplace
	ant._walk(world.route_service.request_route(ant.home.cell, workplace.cell), &"work")

func _load_scoring(test: Node) -> void:
	var world: World = test.make_world()
	for workplace in world.registry.workplaces(): workplace.free()
	var near: Workplace = _place(world, Vector2i(23, 25))
	var far: Workplace = _place(world, Vector2i(25, 25))
	var ants: Array[AntAgent] = world.population.agents()
	# Use a fixed test speed so the extra walk falls between two and three penalties.
	ants[0].speed = AntProfile.new().speed
	_reserve_walk(world, near, ants[1])
	var plan: WorkPlan = world.planner.plan_work(ants[0], ants[0].home, ants[0].needs, ants[0].speed, ants[0].work_time, ants[0]._meal)
	test.expect(plan.workplace == far, "equal travel time prefers fewer working or incoming ants")
	plan.workplace.release_worker(ants[0])
	far.free()
	far = _place(world, Vector2i(26, 25))
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
	var overlay := NavigationOverlay.new()
	overlay.world = world
	overlay.cycle()
	overlay.cycle()
	overlay.hovered = workplace.cell
	var panel: NavigationPanel = preload("res://game/navigation/ui/navigation_panel.tscn").instantiate()
	panel.overlay = overlay
	test.add_child(panel)
	test.expect(workplace.incoming_count() == 1 and workplace.working_count() == 0 and panel._detail.get_parsed_text().contains("0+1 / 4"), "UI immediately includes a reserved walking worker")
	var before: float = overlay.sample(workplace.cell).score
	var travel_seconds := world.planner.travel_seconds(ant.motion.route.cost, ant.movement_speed())
	for step in range(ceili((travel_seconds + 1.0) * 60)):
		ant._physics_process(1.0 / 60.0)
		if ant.status == AntAgent.Status.WORKING: break
	panel.refresh()
	test.expect(workplace.incoming_count() == 0 and workplace.working_count() == 1 and panel._detail.get_parsed_text().contains("1+0 / 4"), "arrival transfers the same worker from incoming to working in the UI")
	ant._physics_process(ant.work.plan.work_seconds + 0.01)
	panel.refresh()
	test.expect(ant.transport.carrying and ant._destination == &"delivery" and workplace.worker_count() == 0 and panel._detail.get_parsed_text().contains("0+0 / 4"), "loaded return is excluded from the displayed enterprise load")
	test.expect(is_equal_approx(before - overlay.sample(workplace.cell).score, world.planner.load_penalty_seconds), "the number on the workplace tile includes the live load penalty")
	test.expect(overlay.sample(workplace.cell).kind == &"work" and overlay.sample(ant.home.cell).kind == &"home", "workplaces and homes use different map label categories")
	panel.free()
	overlay.free()
	for place in world.registry.workplaces(): place.work_slots = 0
	var waiting_ant: AntAgent = world.population.agents()[1]
	var hud: MatchHud = preload("res://game/match/hud/match_hud.tscn").instantiate()
	hud.world = world
	test.add_child(hud)
	waiting_ant._decide()
	test.expect(waiting_ant.waiting_reason == WorkPlan.WaitReason.SLOTS_FULL and hud._waiting.text == (TranslationServer.translate("ui.hud.waiting") % 1) and hud._waiting.visible, "home waiting has a visible full-workplace explanation")
	hud.free()
	world.free()
	await test.get_tree().process_frame

func _replanning_progress(test: Node) -> void:
	var world: World = test.make_world()
	var motion := AntMotion.new()
	motion.navigation = world.route_service
	var cell := Vector2i(25, 25)
	var point: Vector2 = world.route_service.cell_to_world(cell) + Vector2(5, 0)
	motion.follow(world.route_service.make_route([cell, cell + Vector2i.RIGHT]), point)
	test.expect(motion.route.current_index == 1, "replanning keeps forward progress after passing a cell centre")
	motion.follow(motion.route, point)
	test.expect(motion.route.current_index == 1, "reusing a route already at its final waypoint never indexes past it")
	motion.follow(world.route_service.make_route([cell, cell + Vector2i.DOWN]), point)
	test.expect(motion.route.current_index == 0, "replanning visits the centre before a perpendicular turn and cannot cut a wall corner")
	world.free()
	await test.get_tree().process_frame
