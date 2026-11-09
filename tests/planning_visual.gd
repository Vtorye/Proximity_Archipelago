extends "res://tests/ui_runner.gd"
## Rendered reproductions with controlled starting positions and normal game movement.

func _run() -> void:
	seed(20261025)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	await click(Router._current.controls[&"play"])
	await frames(45)
	screen = Router._current
	use_immediate_construction_fixture(screen.world)
	var world: World = screen.world
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var ants: Array[AntAgent] = world.population.agents()
	_reset_ants(ants)
	var stone: Workplace = world.get_node("Workplace2") as Workplace
	for workplace in world.registry.workplaces(): workplace.work_slots = 0
	stone.work_slots = 4
	ants[0]._decide()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	var panel: NavigationPanel = screen.hud.navigation_panel
	world.units.process_mode = Node.PROCESS_MODE_DISABLED
	await click_at(cell_point(stone.cell))
	expect(screen.navigation_overlay.mode == 0 and panel.visible and panel.inspected_cell == stone.cell and panel._detail.text.contains("0+1 / 4"), "a left click shows incoming ants with the navigation overlay off")
	await hover(Vector2i(26, 25))
	expect(panel.inspected_cell == stone.cell and panel._detail.text.contains("0+1 / 4"), "inspection stays on the clicked workplace when the cursor moves")
	await capture("00-workplace-inspector")
	await click_at(cell_point(Vector2i(26, 25)))
	expect(panel.inspected_cell == Vector2i(26, 25), "clicking empty ground selects terrain instead of the workplace")
	world.units.process_mode = Node.PROCESS_MODE_INHERIT
	await key(KEY_N)
	await key(KEY_N)
	await hover(stone.cell)
	expect(panel._detail.text.contains("0+1 / 4"), "walking ant is visible in workplace load")
	await capture("01-heading-to-stone")
	var target := Vector2i(25, 24)
	await key(KEY_SPACE)
	var construction := Router.top_overlay() as ConstructionMenu
	await click(construction.controls[&"apple_tree"])
	await click_at(cell_point(target))
	expect(construction.draft.size() == 1, "bush fixture is painted on a free cell outside the HUD")
	await key(KEY_SPACE)
	await frames(4)
	var bush: Workplace = world.registry.at(target) as Workplace
	expect(bush != null and ants[0].current_workplace == bush, "construction redirects the moving ant")
	await click_at(cell_point(target))
	await hover(Vector2i(26, 25))
	expect(panel.inspected_cell == bush.cell and panel._detail.text.contains("0+1 / 3"), "click pins the new workplace and shows its incoming ant")
	await capture("02-nearer-bush-selected")
	await _until_working(ants[0])
	panel.refresh()
	expect(panel._detail.text.contains("1+0 / 3"), "workplace panel updates on arrival")
	await capture("03-arrived-at-bush")
	for frame in range(150):
		if ants[0]._carrying and ants[0]._destination == &"delivery": break
		await frames(1)
	await hover(target)
	panel.refresh()
	expect(ants[0]._carrying and panel._detail.text.contains("0+0 / 3"), "returning carrier is no longer included in enterprise load")
	await capture("04-returning-with-load")
	await click_at(cell_point(Vector2i(26, 25)))
	world.process_mode = Node.PROCESS_MODE_DISABLED
	_reset_ants(ants)
	for workplace in world.registry.workplaces(): workplace.work_slots = 0
	stone.work_slots = 3
	for index in range(2):
		ants[index]._decide()
		for step in range(1200):
			ants[index]._physics_process(1.0 / 60.0)
			if ants[index].status == AntAgent.Status.WORKING: break
	ants[2]._decide()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	await click_at(cell_point(stone.cell))
	expect(panel._detail.text.contains("2+1 / 3"), "UI separates two working ants from one incoming ant")
	await capture("05-working-plus-incoming")
	ants[3]._decide()
	ants[4]._decide()
	panel.refresh()
	expect(panel._detail.text.contains("2+1 / 3") and ants[4].role == AntAgent.Role.CARRIER and not stone.has_worker(ants[4]), "the carrier leaves all work slots available to workers")
	expect(screen.hud._waiting.visible and screen.hud._waiting.text == (TranslationServer.translate("ui.hud.waiting") % 1), "full slots have a visible home waiting reason")
	await capture("06-full-slots-and-waiting")
	panel.inspect_cell(null)
	world.units.process_mode = Node.PROCESS_MODE_DISABLED
	var courier: AntAgent = ants[4]
	bush._produce(bush.output, 1, true)
	var pending: int = bush.pending_output_amount()
	courier.global_position = world.route_service.cell_to_world(bush.cell)
	courier._decide()
	var walked: Array[Vector2i] = []
	courier.cell_changed.connect(func(_old: Vector2i, next: Vector2i): walked.append(next))
	var attempted_work := false
	for frame in range(90):
		courier._physics_process(1.0 / 30.0)
		attempted_work = attempted_work or courier._pickup_source is Workplace or courier._destination == &"work" or courier.status == AntAgent.Status.WORKING
		await frames(1)
	expect(not attempted_work and courier.cargo.is_empty() and bush.pending_output_amount() == pending and not bush.has_worker(courier), "the carrier ignores a bush without working or collecting its output")
	expect(walked.size() >= 2 and courier._destination == &"wander", "an idle carrier visibly walks around its nest")
	await hover(bush.cell)
	await capture("06b-carrier-ignores-bush")
	await key(KEY_N)
	await capture("06c-idle-carrier-walk")
	await key(KEY_N)
	await key(KEY_N)
	world.units.process_mode = Node.PROCESS_MODE_INHERIT
	var depot_cell := Vector2i(27, 27)
	var nest: BuildOption = load("res://game/building/options/house.tres")
	expect(world.build_controller.try_build(nest, depot_cell), "the carrier scenario builds a small depot")
	var depot: House = world.registry.at(depot_cell) as House
	if depot != null:
		depot.storage_capacity = 8
		world.inventory.add(world.inventory.type_by_id(&"royal"), 1)
		var base_option: BuildOption = load("res://game/building/options/base_nest.tres")
		var base_cell := Vector2i(29, 27)
		expect(world.build_controller.try_build(base_option, base_cell), "the shipment scenario builds a nearer base nest")
		var base := world.registry.at(base_cell) as House
		var wood: ResourceType = world.inventory.type_by_id(&"wood")
		var stock := ResourceAmount.new()
		stock.type = wood
		stock.amount = 6
		world.inventory.deposit(depot, [stock])
		courier._decide()
		for frame in range(150):
			if courier._shipment: break
			await frames(1)
		expect(courier._shipment and WorldInventory.cargo_size(courier.cargo) == 6, "the main carrier loads six units from the small depot")
		expect(courier._delivery_nest == base, "the carrier takes its shipment toward the nearest base nest")
		await key(KEY_N)
		await capture("07-carrier-with-load")
		for frame in range(150):
			if courier.cargo.is_empty(): break
			await frames(1)
		expect(courier.cargo.is_empty() and world.inventory.depot_quantity(base, wood) == 6, "the shipment physically reaches the new base inventory")
		await capture("08-delivered-to-nearest-base")
	Router.goto(&"main_menu")
	await frames(45)
	_finish()

func _reset_ants(ants: Array[AntAgent]) -> void:
	for ant in ants:
		ant._release_work()
		ant.needs.eat()
		ant.global_position = ant.home.global_position
		ant._carrying = false
		ant._destination = &"home"
		ant._timer = 1000.0
		ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
		ant._set_status(AntAgent.Status.HOME)

func _until_working(ant: AntAgent) -> void:
	for frame in range(180):
		if ant.status == AntAgent.Status.WORKING: return
		await frames(1)
	expect(false, "walking ant reaches its selected workplace")

func hover(cell: Vector2i) -> void:
	get_viewport().warp_mouse(cell_point(cell))
	var motion := InputEventMouseMotion.new()
	motion.position = cell_point(cell)
	motion.global_position = motion.position
	get_viewport().push_input(motion, true)
	await frames(9)
	panel_refresh()
func panel_refresh() -> void:
	screen.hud.navigation_panel.refresh()
