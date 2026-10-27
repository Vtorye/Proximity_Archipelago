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
	var world: World = screen.world
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var ants: Array[AntAgent] = world.population.agents()
	_reset_ants(ants)
	var stone: Workplace = world.get_node("Workplace2") as Workplace
	for workplace in world.registry.workplaces(): workplace.work_slots = 0
	stone.work_slots = 4
	ants[0]._decide()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	var menu: BuildMenu = await select_cell(stone.cell)
	expect(menu._description.text.contains("0+1/4"), "walking ant is visible in workplace load")
	await capture("01-heading-to-stone")
	await frames(45)
	await key(KEY_ESCAPE)
	var target: Vector2i = world.route_service.world_to_cell(ants[0].global_position) + Vector2i(0, -1)
	menu = await select_cell(target)
	await click(menu.controls[&"apple_tree"])
	await frames(4)
	var bush: Workplace = world.registry.at(target) as Workplace
	expect(bush != null and ants[0].current_workplace == bush, "construction redirects the moving ant")
	menu = await select_cell(target)
	expect(menu._description.text.contains("0+1/3"), "new workplace immediately shows its incoming ant")
	await capture("02-nearer-bush-selected")
	await _until_working(ants[0])
	expect(menu._description.text.contains("1+0/3"), "workplace panel updates on arrival")
	await capture("03-arrived-at-bush")
	for frame in range(150):
		if ants[0]._carrying and ants[0]._destination == &"home": break
		await frames(1)
	expect(ants[0]._carrying and menu._description.text.contains("0+0/3"), "returning carrier is no longer included in enterprise load")
	await capture("04-returning-with-load")
	await key(KEY_ESCAPE)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	_reset_ants(ants)
	for workplace in world.registry.workplaces(): workplace.work_slots = 0
	stone.work_slots = 4
	for index in range(2):
		ants[index]._decide()
		for step in range(1200):
			ants[index]._physics_process(1.0 / 60.0)
			if ants[index].status == AntAgent.Status.WORKING: break
	ants[2]._decide()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	menu = await select_cell(stone.cell)
	expect(menu._description.text.contains("2+1/4"), "UI separates two working ants from one incoming ant")
	await capture("05-working-plus-incoming")
	ants[3]._decide()
	ants[4]._decide()
	expect(menu._description.text.contains("2+2/4"), "last slot is reserved before the fourth ant arrives")
	expect(screen.hud._waiting.visible and screen.hud._waiting.text == "Ждут мест: 1", "full slots have a visible home waiting reason")
	await capture("06-full-slots-and-waiting")
	await key(KEY_ESCAPE)
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
