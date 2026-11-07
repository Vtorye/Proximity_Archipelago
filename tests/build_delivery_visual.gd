extends "res://tests/ui_runner.gd"
## The real build palette queues an order, normal-speed ants transport it and assemble it.
func _run() -> void:
	seed(20261108)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	await click(Router._current.controls[&"play"])
	await frames(20)
	screen = Router._current
	var world: World = screen.world
	var cell := Vector2i(27, 27)
	await key(KEY_SPACE)
	var menu := Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"house"])
	await click_at(cell_point(cell))
	expect(menu.draft.size() == 1 and menu.draft.budget_check().allowed(), "a real two-resource house order fits the starting budget")
	await key(KEY_SPACE)
	var site := world.registry.at(cell) as ConstructionSite
	expect(site != null and world.population.count() == 5, "applying the plan queues a non-operational house")
	await click_at(cell_point(cell), MOUSE_BUTTON_RIGHT)
	expect(screen.hud.navigation_panel._detail.text.contains("0 / 10") and screen.hud.navigation_panel._detail.text.contains("0 / 20"), "the inspector shows undelivered wood and stone")
	await capture("01-waiting-for-materials", 20)
	var delivered := false
	var assembling := false
	for frame in range(2400):
		await frames(1)
		if not is_instance_valid(site) or not site.active: break
		if not delivered and site.material_count() > 0:
			delivered = true
			screen.hud.navigation_panel.refresh()
			await capture("02-delivering-materials", 30)
		if not assembling and site.progress > 0:
			assembling = true
			screen.hud.navigation_panel.refresh()
			await capture("03-worker-assembly", 20)
	expect(delivered and assembling and world.registry.at(cell) is House and world.population.count() == 10, "physical deliveries precede worker assembly and resident spawning")
	await capture("04-completed-barracks", 30)
	await click_at(cell_point(cell))
	var nest := Router.top_overlay() as NestMenu
	expect(nest != null and nest.house == world.registry.at(cell), "only the finished house opens its real inventory and residents")
	await capture("05-finished-nest-window", 20)
	await key(KEY_ESCAPE)
	Router.goto(&"main_menu")
	await frames(25)
	_finish()
