extends "res://tests/ui_runner.gd"
## A real input walkthrough. The colony uses the shipped budget and normal simulation speed.

func _run() -> void:
	seed(20261107)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	await click(Router._current.controls[&"maps"])
	await frames(25)
	var editor: Control = Router._current
	var found := false
	for index in range(editor._saved.item_count):
		if editor._saved.get_item_metadata(index) == "builtin/tidal_shards":
			editor._saved.select(index)
			found = true
			break
	expect(found, "the authored archipelago is available without importing a file")
	await click(_editor_button(editor, "ui.map.load"))
	editor._camera.set_level(WorldCamera.MIN_LEVEL)
	expect(editor._title.text == "Осколки прилива" and not editor._dirty, "the bundled map opens ready to play or edit")
	await capture("01-authored-map-editor", 30)
	await click(_editor_button(editor, "ui.menu.play"))
	await frames(30)
	expect(Router.current_screen_key() == &"match", "the authored map launches directly from the map menu")
	screen = Router._current
	var world: World = screen.world
	expect(world.map_size == Vector2i(136, 84) and world.population.count() == 5, "the full-size authored map starts with its intended colony")
	screen.camera.set_level(0)
	await click(screen.hud.controls[&"zoom_out"])
	expect(screen.camera.level == WorldCamera.MIN_LEVEL and screen.camera.zoom == Vector2(0.25, 0.25) and screen.hud.controls[&"zoom_out"].disabled, "the overview zoom button reaches its quarter-scale limit")
	await capture("02-archipelago-overview", 45)
	screen.hud.hide()
	await capture("02a-unobstructed-archipelago", 30)
	screen.hud.show()
	screen.camera.set_level(2)
	screen.camera.position = world.logistics.main_nest.global_position
	screen.camera.force_update_scroll()
	await frames(5)
	await capture("03-starter-bay", 30)
	await key(KEY_SPACE)
	var menu := Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"house"])
	await click_at(cell_point(Vector2i(64, 42)))
	await click_at(cell_point(Vector2i(74, 40)))
	await click(menu.controls[&"road"])
	for x in range(64, 76):
		await click_at(cell_point(Vector2i(x, 44)))
	for y in range(39, 44):
		await click_at(cell_point(Vector2i(75, y)))
	for y in range(41, 44):
		await click_at(cell_point(Vector2i(65, y)))
	await click_at(cell_point(Vector2i(68, 45)))
	await click_at(cell_point(Vector2i(68, 46)))
	expect(menu.draft.budget_check().allowed(), "the real starter budget pays for both camps and connecting paths")
	await capture("04-camps-and-roads-plan", 30)
	await key(KEY_SPACE)
	expect(world.build_controller.construction.sites.size() > 0 and world.population.count() == 5, "committing both camps queues physical construction")
	for second in range(120):
		if world.population.count() >= 15: break
		await frames(30)
		# Keep the real task loop active while normal-speed ants build the camps.
		for index in range(world.tasks.slots.size()):
			if world.tasks.can_pay(index):
				world.tasks.submit(index)
				break
	expect(world.population.count() == 15, "delivered and assembled camps expand the colony to fifteen ants")
	var claimed := false
	for second in range(45):
		for button in screen.hud.task_panel.find_children("*", "Button", true, false):
			if not button.get_meta(&"cancel", true) and not button.disabled:
				await click(button)
				claimed = true
				break
		if claimed: break
		await frames(30)
	expect(claimed and world.tasks.completed_count >= 1, "working camps fund a task reward during normal-speed play")
	await capture("05-earned-expansion-crown", 30)
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	screen.camera.position = world.route_service.cell_to_world(Vector2i(67, 21))
	screen.camera.force_update_scroll()
	await click(menu.controls[&"base_nest"])
	await click_at(cell_point(Vector2i(67, 21)))
	await capture("06-northern-base-plan", 30)
	await key(KEY_SPACE)
	var base := world.registry.at(Vector2i(67, 21)) as House
	expect(base != null and base.is_main_nest and world.population.count() == 20, "an earned crown establishes a base on the northern stone island")
	await frames(300)
	await click_at(cell_point(Vector2i(65, 19)))
	await capture("07-northern-stone-colony", 30)
	await key(KEY_N)
	await key(KEY_N)
	await click_at(cell_point(Vector2i(67, 21)), MOUSE_BUTTON_RIGHT)
	# A house click opens its window; close it before inspecting the world field.
	if Router.has_overlay(): await key(KEY_ESCAPE)
	await capture("08-island-navigation", 30)
	await key(KEY_N)
	screen.camera.set_level(WorldCamera.MIN_LEVEL)
	await capture("09-developed-archipelago", 45)
	Router.goto(&"main_menu")
	await frames(35)
	_finish()

func _editor_button(editor: Control, label: String) -> Button:
	for button in editor.find_children("*", "Button", true, false):
		if button.text == label:
			return button
	return null
