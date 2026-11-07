extends "res://tests/ui_runner.gd"
func _run() -> void:
	seed(20261031)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(40)
	await click(Router._current.controls[&"play"])
	await frames(40)
	screen = Router._current
	use_immediate_construction_fixture(screen.world)
	var tasks: TaskDirector = screen.world.tasks
	expect(tasks != null and tasks.slots.size() == 3, "three task cards replace the fixed objective")
	for button in screen.hud.task_panel.find_children("*", "Button", true, false):
		expect(screen.hud.task_panel.get_global_rect().encloses(button.get_global_rect()), "all three initial task actions fit without scrolling")
	await capture("01-three-requests", 30)
	var stable_button: Button = screen.hud.task_panel.find_children("*", "Button", true, false)[0]
	screen.world.inventory.add(screen.world.inventory.type_by_id(&"wood"), 1)
	screen.world.match_controller.time_changed.emit(179)
	await frames(4)
	expect(is_instance_valid(stable_button), "inventory and timer updates preserve the button being clicked")
	var before: float = screen.world.match_controller.time_remaining
	await action(false)
	expect(screen.world.match_controller.time_remaining > before + 24 and tasks.closed == 1, "claim button pays the request and adds time")
	await capture("02-time-and-rare-reward", 30)
	var royal: ResourceType = screen.world.inventory.type_by_id(&"royal")
	var quantity: int = screen.world.inventory.quantity(royal)
	await action(true)
	expect(tasks.closed == 2 and screen.world.inventory.quantity(royal) == quantity, "cancel button pays without granting a rare reward")
	await capture("03-cancelled-request", 30)
	# Controlled progression fixture only: production definitions retain their real starting stock.
	for type in screen.world.inventory.registered_types(): screen.world.inventory.add(type, 1000)
	await frames(5)
	for index in range(3): await action(false)
	expect(tasks.level == 2, "closing the first pool advances the colony")
	await capture("04-level-two-and-road-unlock", 30)
	await key(KEY_SPACE)
	var editor: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	expect(editor.controls.has(&"road_plus") and not editor.controls.has(&"road") and editor.controls.has(&"canteen"), "palette replaces the ordinary road with its upgrade and offers the rare-resource canteen")
	await click(editor.controls[&"road_plus"])
	await click_at(cell_point(Vector2i(27, 24)))
	await click(editor.controls[&"canteen"])
	await click_at(cell_point(Vector2i(28, 24)))
	await capture("05-reward-buildings-in-plan", 30)
	await key(KEY_SPACE)
	expect(screen.world.registry.at(Vector2i(28, 24)) is Canteen, "rare resources buy another working feeding point")
	expect(screen.world.route_service.entry_cost(Vector2i(27, 24)) < 0.35, "unlocked road changes actual travel time")
	await frames(5)
	for index in range(5): await action(false)
	expect(tasks.level == 3 and screen.world.prices.global_multiplier < 1.0, "second-stage reward discounts construction")
	await capture("06-level-three-discount", 30)
	for index in range(5): await action(false)
	expect(tasks.level == 4 and screen.world.population.agents()[0].speed > 24.0, "later stages speed up ants and repeat with harder prices")
	await capture("07-speed-upgrade-and-repeat", 30)
	await _check_resource_facilities()
	await click(screen.hud.controls[&"settings"])
	await click(Router.top_overlay().controls[&"settings"])
	await click(Router.top_overlay().controls[&"ui_scale_plus"])
	await click(Router.top_overlay().controls[&"done"])
	await click(Router.top_overlay().controls[&"resume"])
	await capture("08-task-panel-scale-100", 30)
	preload("res://tests/pixel_font_checks.gd").verify(self, screen.hud)
	expect(get_viewport().get_visible_rect().encloses(screen.hud.task_panel.get_global_rect()), "task board fits at the largest UI scale")
	await key(KEY_N)
	await key(KEY_N)
	expect(screen.navigation_overlay.reference_speed > 24.0, "navigation display reflects the speed upgrade")
	await action(false)
	expect(tasks.closed == 1, "task buttons remain usable in the navigation explanation mode")
	expect(not screen.hud.task_panel.get_global_rect().intersects(screen.hud._toast.get_global_rect()), "task board leaves the navigation hint unobstructed at full scale")
	expect(not screen.hud.navigation_panel.get_global_rect().intersects(screen.hud.task_panel.get_global_rect()), "priority explanation and task offers remain separate at full scale")
	expect(get_viewport().get_visible_rect().encloses(screen.hud.navigation_panel.get_global_rect()), "priority explanation fits the viewport")
	await capture("09-navigation-and-task-actions", 30)
	await key(KEY_N)
	screen.world.match_controller._process(100000.0)
	await frames(8)
	expect(Router.top_overlay().payload.development_level == 4, "result reports the reached colony level")
	await capture("10-task-expiry-result", 30)
	preload("res://tests/pixel_font_checks.gd").verify(self, Router.top_overlay())
	await click(Router.top_overlay().controls[&"main"])
	await frames(40)
	AppSettings.reset_defaults()
	_finish()
func action(cancel: bool) -> void:
	await frames(4)
	for button in screen.hud.task_panel.find_children("*", "Button", true, false):
		if button.get_meta(&"cancel", not cancel) == cancel and not button.disabled:
			await click(button)
			return
	expect(false, "an affordable task action is available")

func _check_resource_facilities() -> void:
	var world: World = screen.world
	world.units.process_mode = Node.PROCESS_MODE_DISABLED
	var timber := world.get_node("Workplace") as Workplace
	var stone := world.get_node("Workplace2") as Workplace
	var berries := world.get_node("AppleTree") as Workplace
	var targets := {&"sawmill": timber, &"quarry": stone, &"farm": berries}
	var slots: int = stone.work_slots
	await key(KEY_SPACE)
	var menu := Router.top_overlay() as ConstructionMenu
	for id in targets:
		expect(menu.controls.has(id), "completed tasks unlock the resource facility in construction")
		await click(menu.controls[id])
		await click_at(cell_point(targets[id].cell))
	expect(menu.draft.size() == 3, "all three facilities can be planned on existing resource cells")
	await capture("07a-resource-facilities-plan", 30)
	await key(KEY_SPACE)
	expect(stone.improvement != null and stone.work_slots == slots + 2 and timber.improvement != null and berries.improvement != null, "applying the plan installs all facilities and increases their worker slots")
	await click_at(cell_point(stone.cell))
	await capture("07b-quarry-workplace-info", 30)
	stone.finite_supply = true
	stone.remaining_supply = 2
	var worker: AntAgent = world.population.agents()[0]
	worker._release_work()
	worker._clear_cargo()
	stone.take_output(1000000)
	worker.global_position = world.route_service.cell_to_world(stone.cell)
	worker.needs.eat()
	worker._decide()
	for frame in range(240):
		if stone.remaining_supply == 0: break
		worker._physics_process(1.0 / 30.0)
		await frames(1)
	screen.hud.navigation_panel.refresh()
	expect(stone.remaining_supply == 0 and screen.hud.navigation_panel._detail.text.contains("Запас: 0"), "finite resource exhaustion appears in the workplace inspector")
	await capture("07c-exhausted-quarry", 30)
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"demolish"])
	await click_at(cell_point(stone.cell))
	await key(KEY_SPACE)
	expect(world.registry.at(stone.cell) == stone and stone.improvement == null and stone.remaining_supply == 0, "demolishing the quarry preserves its exhausted source")
	expect(not (stone.get_node("Sprite") as Sprite2D).visible, "removing the facility leaves no raw resource image on an exhausted tile")
	await capture("07d-facility-demolished-source-kept", 30)
	stone.remaining_supply = 1
	expect((stone.get_node("Sprite") as Sprite2D).visible, "a replenished resource is visible before its last harvest")
	screen.hud.navigation_panel.refresh()
	await capture("07e-last-visible-resource", 30)
	worker._release_work()
	worker._clear_cargo()
	stone.take_output(1000000)
	worker.global_position = world.route_service.cell_to_world(stone.cell)
	worker.needs.eat()
	worker._decide()
	for frame in range(150):
		if stone.remaining_supply == 0: break
		worker._physics_process(1.0 / 30.0)
		await frames(1)
	expect(stone.remaining_supply == 0 and not (stone.get_node("Sprite") as Sprite2D).visible and WorldInventory.cargo_size(worker.cargo) == 1, "the last harvest removes the resource image and leaves its cargo with the worker")
	screen.hud.navigation_panel.refresh()
	await capture("07f-depleted-resource-disappeared", 30)
	world.units.process_mode = Node.PROCESS_MODE_INHERIT
