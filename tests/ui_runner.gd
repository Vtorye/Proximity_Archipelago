extends Node
## Runs the real GUI input pipeline, captures rendered frames, and checks visible behavior.
var failures: Array[String] = []
var assertions := 0
var captures: Array[String] = []
var screen: Node
var _output: String
var nested_viewport := false
var display_size := Vector2i.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not nested_viewport:
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--virtual-resolution="):
				var dimensions: PackedStringArray = argument.get_slice("=", 1).split("x")
				var viewport := SubViewport.new()
				viewport.size = Vector2i(640, 360)
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				viewport.handle_input_locally = true
				add_child(viewport)
				var child: Node = get_script().new()
				child.nested_viewport = true
				child.display_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
				viewport.add_child(child)
				return
	_output = OS.get_environment("COLONY_EVIDENCE_DIR")
	DirAccess.make_dir_recursive_absolute(_output)
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		print("UI FAIL ", message)

func frames(count: int = 12) -> void:
	for index in range(count):
		await get_tree().process_frame

func capture(label: String, linger: int = 12) -> Image:
	await RenderingServer.frame_post_draw
	var path: String = _output.path_join(label + ".png")
	var target: Vector2i = display_size if display_size != Vector2i.ZERO else get_window().size
	var image: Image = PixelCapture.from_viewport(get_viewport(), target)
	image.save_png(path)
	captures.append(label)
	print("CAPTURE ", label)
	await frames(linger)
	return image

func click_at(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
	await frames(4)

func click(control: Control) -> void:
	expect(is_instance_valid(control) and control.is_visible_in_tree(), "clicked control is visible")
	if is_instance_valid(control):
		var ancestor: Node = control.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				ancestor.ensure_control_visible(control)
				await frames(2)
			ancestor = ancestor.get_parent()
		await click_at(control.get_global_rect().get_center())

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await frames(2)

func cell_point(cell: Vector2i) -> Vector2:
	var map: TileMapLayer = screen.world.get_node("Map") as TileMapLayer
	return map.get_global_transform_with_canvas() * map.map_to_local(cell)

func select_cell(cell: Vector2i) -> BuildMenu:
	await click_at(cell_point(cell), MOUSE_BUTTON_RIGHT)
	await frames(6)
	var menu: BuildMenu = Router.top_overlay() as BuildMenu
	expect(menu != null and screen.selection.selected and screen.selection.cell == cell, "mouse selects the requested map cell")
	return menu

func validate_popup(menu: BuildMenu) -> void:
	if menu == null:
		return
	var rect: Rect2 = menu._panel.get_global_rect()
	var viewport: Rect2 = get_viewport().get_visible_rect()
	expect(viewport.encloses(rect), "build menu stays fully inside viewport")
	expect(not rect.intersects(screen.selection.screen_rect().grow(-1)), "build menu does not cover selected cell")
	for obstacle in menu.context.obstacles:
		expect(not rect.intersects(obstacle), "build menu does not cover objectives")
	if menu._message.visible:
		expect(not rect.intersects(menu._message.get_global_rect()), "help never covers construction choices")
	expect(rect.position.y >= 60 and rect.end.y <= viewport.end.y - 72, "build menu keeps permanent controls accessible")

func _run() -> void:
	seed(20261025)
	AppSettings.reset_defaults()
	var boot: Node = load("res://boot.tscn").instantiate()
	get_viewport().add_child(boot)
	await frames(35)
	expect(Router.current_screen_key() == &"main_menu", "main menu starts")
	if "--layout-only" in OS.get_cmdline_user_args():
		await _layout_only()
		_finish()
		return
	await capture("01-main-menu")
	await key(KEY_TAB)
	expect(get_viewport().gui_get_focus_owner() != null, "keyboard focus is visible")
	await capture("02-keyboard-focus")
	await click(Router._current.controls[&"settings"])
	await frames()
	var settings: MenuBase = Router.top_overlay()
	expect(settings != null and not get_tree().paused, "main-menu settings open without pausing a session")
	await capture("03-main-settings")
	await click(settings.controls[&"volume"])
	await click(settings.controls[&"vsync"])
	await click(settings.controls[&"show_grid"])
	await click(settings.controls[&"reduced_motion"])
	expect(AppSettings.master_volume < 65 and not AppSettings.vsync and AppSettings.show_grid and AppSettings.reduced_motion, "settings controls apply real values")
	await capture("04-settings-modified")
	var config := ConfigFile.new()
	expect(config.load(AppSettings.PATH) == OK and config.get_value("interface", "grid", false), "settings persist to disk")
	await click(settings.controls[&"reset"])
	expect(AppSettings.master_volume == 70 and AppSettings.vsync and not AppSettings.show_grid and not AppSettings.reduced_motion, "reset restores defaults")
	await capture("05-settings-reset")
	await key(KEY_ESCAPE)
	expect(not Router.has_overlay(), "escape returns from main settings")
	await click(Router._current.controls[&"play"])
	await frames(60)
	screen = Router._current
	expect(Router.current_screen_key() == &"match" and screen.world.population.count() == 5, "play enters a live colony")
	expect((screen.world.registry.at(Vector2i(49, 50)) as House).residents.size() == 5, "starter nest owns five residents")
	expect(screen.world.population.agents().any(func(ant: AntAgent): return ant.status == AntAgent.Status.WALKING), "starter ants visibly leave home")
	await capture("06-colony")
	await click_at(Vector2(320, 200))
	expect(not Router.has_overlay(), "left click never opens construction")
	var cell := Vector2i(51, 50)
	var menu: BuildMenu = await select_cell(cell)
	validate_popup(menu)
	var locked_level: int = screen.camera.level
	await click_at(Vector2(20, 280), MOUSE_BUTTON_WHEEL_UP)
	expect(screen.camera.level == locked_level and Router.top_overlay() == menu, "wheel cannot zoom while construction is open")
	await click_at(cell_point(Vector2i(52, 50)), MOUSE_BUTTON_RIGHT)
	expect(not Router.has_overlay() and not screen.selection.selected, "second right click only closes construction")
	menu = await select_cell(cell)
	await click_at(Vector2(20, 280))
	expect(not Router.has_overlay(), "left click outside closes construction")
	menu = await select_cell(cell)
	var motion := InputEventMouseMotion.new()
	motion.position = menu.controls[&"road"].get_global_rect().get_center()
	motion.global_position = motion.position
	get_viewport().push_input(motion, true)
	await frames(3)
	expect(not menu._message.text.is_empty(), "disabled placement explains its reason inline")
	validate_popup(menu)
	await capture("07-placement-help")
	await key(KEY_ESCAPE)
	menu = await select_cell(cell)
	await frames(2)
	var bright: Image = await capture("07-selection-bright", 0)
	await frames(18)
	var dim: Image = await capture("08-selection-dim")
	_check_brackets(bright, dim, screen.selection.screen_rect())
	for item in [["left", Vector2(24, 196)], ["right", Vector2(616, 196)], ["top", Vector2(400, 84)], ["bottom", Vector2(350, 308)]]:
		await key(KEY_ESCAPE)
		var desired: Vector2 = item[1]
		var viewport: Vector2 = get_viewport().get_visible_rect().size
		screen.camera.position = screen.world.route_service.cell_to_world(cell) - (desired - viewport / 2.0) / screen.camera.zoom
		screen.camera.force_update_scroll()
		await frames(4)
		menu = await select_cell(cell)
		validate_popup(menu)
		await capture("09-edge-" + item[0])
	await key(KEY_ESCAPE)
	screen.camera.position = Vector2(800, 800)
	screen.camera.force_update_scroll()
	await frames(4)
	await click(screen.hud.controls[&"zoom_in"])
	expect(screen.camera.level == 3, "zoom in button")
	await capture("10-zoom-in")
	await click(screen.hud.controls[&"zoom_out"])
	expect(screen.camera.level == 2, "zoom out button")
	await click_at(Vector2(320, 200), MOUSE_BUTTON_WHEEL_DOWN)
	expect(screen.camera.level == 1, "mouse wheel changes zoom")
	await capture("11-zoom-out")
	screen.camera.set_level(2)
	await frames(3)
	var map: TileMapLayer = screen.world.get_node("Map") as TileMapLayer
	menu = await select_cell(Vector2i(55, 54))
	await click(menu.controls[&"road"])
	expect(map.get_cell_atlas_coords(Vector2i(55, 54)) == Vector2i(2, 0), "road action paints the road material")
	await capture("12a-road-built")
	menu = await select_cell(Vector2i(55, 54))
	await click(menu.controls[&"ground"])
	expect(map.get_cell_atlas_coords(Vector2i(55, 54)) == Vector2i(1, 0), "soil action restores the soil material")
	await capture("12b-soil-built")
	menu = await select_cell(Vector2i(55, 54))
	await click(menu.controls[&"apple_tree"])
	var berries: Workplace = screen.world.registry.at(Vector2i(55, 54)) as Workplace
	expect(berries != null and berries.output_amount == 3, "berry action creates a productive food workplace")
	await capture("12c-berries-built")
	menu = await select_cell(Vector2i(55, 54))
	await click(menu.controls[&"demolish"])
	await click(menu.controls[&"demolish"])
	await frames(4)
	menu = await select_cell(Vector2i(55, 54))
	expect(menu != null and not menu.controls[&"house"].disabled, "empty safe cell permits a nest")
	await capture("12-build-choices")
	await click(menu.controls[&"house"])
	await frames(8)
	expect(screen.world.population.count() == 10 and not Router.has_overlay(), "nest builds and creates configured population")
	await capture("13-nest-built")
	menu = await select_cell(Vector2i(55, 54))
	expect(menu.controls[&"house"].disabled, "occupied nest cell rejects replacement")
	await click(menu.controls[&"demolish"])
	validate_popup(menu)
	await capture("14-demolition-confirmation")
	expect(menu._confirming and screen.world.population.count() == 10, "demolition waits for confirmation")
	await click(menu.controls[&"cancel_demolish"])
	expect(not menu._confirming and screen.world.population.count() == 10, "cancel preserves the building and residents")
	await capture("15-demolition-cancelled")
	await click(menu.controls[&"demolish"])
	await click(menu.controls[&"demolish"])
	await frames(8)
	expect(screen.world.population.count() == 5 and screen.world.registry.at(Vector2i(55, 54)) == null, "confirmed demolition removes exactly that nest")
	await capture("16-demolition-complete")
	menu = await select_cell(Vector2i(53, 51))
	expect(menu.controls[&"demolish"].disabled, "last feeding point is protected")
	await capture("17-feeding-point-protected")
	await click(screen.hud.controls[&"pause"])
	expect(not screen.selection.selected and not Router.top_overlay() is BuildMenu, "pause closes construction with a single click")
	await frames(8)
	var paused_time: float = screen.world.match_controller.time_remaining
	var satiety: float = screen.world.population.agents()[0].needs.satiety
	await capture("18-pause")
	await frames(20)
	expect(is_equal_approx(screen.world.match_controller.time_remaining, paused_time) and is_equal_approx(screen.world.population.agents()[0].needs.satiety, satiety), "pause freezes timer and hunger")
	await click(Router.top_overlay().controls[&"settings"])
	await frames(8)
	await capture("19-nested-settings")
	settings = Router.top_overlay()
	await click(settings.controls[&"show_grid"])
	await click(settings.controls[&"reduced_motion"])
	await capture("20-grid-setting")
	await key(KEY_ESCAPE)
	expect(get_tree().paused and Router.top_overlay() != null, "closing nested settings keeps pause ownership")
	await click(Router.top_overlay().controls[&"resume"])
	await frames(8)
	expect(not get_tree().paused, "resume unpauses the session")
	await click(screen.hud.controls[&"pause"])
	var old_world: World = screen.world
	await click(Router.top_overlay().controls[&"restart"])
	await frames(50)
	screen = Router._current
	expect(not is_instance_valid(old_world) and not get_tree().paused and not Router.has_overlay(), "pause restart retires the old world and clears pause ownership")
	expect(screen.world.population.count() == 5 and screen.world.match_controller.time_remaining > 178.0, "pause restart resets the population and match timer")
	expect(AppSettings.show_grid and AppSettings.reduced_motion, "pause restart preserves player settings")
	await capture("20a-pause-restart")
	menu = await select_cell(Vector2i(51, 50))
	await capture("21-reduced-motion-grid")
	await key(KEY_ESCAPE)
	# A real camera drag must move the map, not activate a cell.
	var old_position: Vector2 = screen.camera.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(320, 200)
	get_viewport().push_input(press, true)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(360, 220)
	drag.relative = Vector2(40, 20)
	get_viewport().push_input(drag, true)
	press.pressed = false
	get_viewport().push_input(press, true)
	await frames(5)
	expect(screen.camera.position != old_position, "held left mouse pans without opening construction")
	await capture("22-camera-pan")
	# Select a water tile by centering its neighborhood in the live camera.
	screen.camera.position = Vector2(50 * 16 + 8, 20 * 16 + 8)
	screen.camera.force_update_scroll()
	await frames(5)
	menu = await select_cell(Vector2i(50, 20))
	expect(menu.controls[&"road"].disabled and menu.controls[&"house"].disabled, "water denies construction")
	await capture("23-water-selection")
	await key(KEY_ESCAPE)
	screen.camera.position = Vector2(800, 800)
	screen.camera.force_update_scroll()
	await frames(5)
	var stock: WorldInventory = screen.world.inventory
	stock.begin_update()
	for type in stock.registered_types():
		stock.add(type, maxi(0, screen.world.match_controller.target_amount - stock.quantity(type)))
	stock.end_update()
	await frames(8)
	expect(get_tree().paused and Router.top_overlay() != null and not Router.top_overlay().dismissable, "victory presents a final paused result")
	await capture("24-victory")
	await key(KEY_ESCAPE)
	expect(Router.has_overlay() and get_tree().paused, "escape cannot dismiss the final result")
	await click(Router.top_overlay().controls[&"again"])
	await frames(50)
	screen = Router._current
	expect(Router.current_screen_key() == &"match" and not get_tree().paused and screen.world.population.count() == 5, "restart creates a clean session")
	screen.world.match_controller._process(500.0)
	await frames(8)
	await capture("25-defeat")
	await click(Router.top_overlay().controls[&"main"])
	await frames(50)
	expect(Router.current_screen_key() == &"main_menu" and not Router.has_overlay() and not get_tree().paused, "result returns to an unpaused clean main menu")
	await capture("26-return-to-menu")
	# A result arriving during an exit must never survive that session.
	await click(Router._current.controls[&"play"])
	await frames(50)
	screen = Router._current
	Router.goto(&"main_menu")
	screen.world.match_controller._finish(MatchController.Result.LOSS, MatchController.Reason.TIME_UP)
	await frames(45)
	expect(Router.current_screen_key() == &"main_menu" and not Router.has_overlay() and not get_tree().paused, "completion during navigation cannot reopen a result")
	AppSettings.reset_defaults()
	_finish()

func _check_brackets(bright: Image, dim: Image, rect: Rect2) -> void:
	# Four independent pixel regions verify both presence and visible animation.
	var factor: float = floorf(minf(float(bright.get_width()) / 640.0, float(bright.get_height()) / 360.0))
	var scale := Vector2.ONE * factor
	var offset: Vector2 = (Vector2(bright.get_size()) - Vector2(640, 360) * factor) / 2.0
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var a := 0.0
		var b := 0.0
		var difference := 0.0
		var pixel: Vector2i = Vector2i(corner * scale + offset)
		for y in range(-4, 5):
			for x in range(-4, 5):
				var point: Vector2i = pixel + Vector2i(x, y)
				if Rect2i(Vector2i.ZERO, bright.get_size()).has_point(point):
					var first: Color = bright.get_pixelv(point)
					var second: Color = dim.get_pixelv(point)
					a = maxf(a, minf(first.r, minf(first.g, first.b)))
					b = maxf(b, minf(second.r, minf(second.g, second.b)))
					difference = maxf(difference, absf(first.r - second.r))
		expect(maxf(a, b) > 0.8, "selected tile has a white corner bracket")
		expect(difference > 0.1, "corner bracket visibly blinks")

func _layout_only() -> void:
	var dimensions: Vector2i = display_size if display_size != Vector2i.ZERO else get_window().size
	var tag: String = "layout-%dx%d-" % [dimensions.x, dimensions.y]
	await capture(tag + "main")
	await click(Router._current.controls[&"settings"])
	await frames(10)
	await capture(tag + "settings")
	await key(KEY_ESCAPE)
	await click(Router._current.controls[&"play"])
	await frames(50)
	screen = Router._current
	var menu: BuildMenu = await select_cell(Vector2i(51, 50))
	validate_popup(menu)
	await capture(tag + "build")
	await key(KEY_ESCAPE)
	await click(screen.hud.controls[&"pause"])
	await frames(8)
	await capture(tag + "pause")
	await click(Router.top_overlay().controls[&"main"])
	await frames(45)
	expect(not get_tree().paused and Router.current_screen_key() == &"main_menu", "layout navigation remains usable")

func _finish() -> void:
	if failures.is_empty() and Router.current_screen_key() == &"main_menu":
		# Exercise the real quit button; application shutdown also retires audio playback.
		var point: Vector2 = Router._current.controls[&"quit"].get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		get_viewport().push_input(motion, true)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			get_viewport().push_input(event, true)
		expect(AppSettings.quitting, "quit button requests application shutdown")
	var report := {"source_revision": OS.get_environment("COLONY_SOURCE_REVISION"), "assertions": assertions, "failures": failures, "captures": captures, "render_size": str(get_viewport().get_texture().get_size()), "window_size": str(get_window().size), "display_size": str(display_size)}
	var file := FileAccess.open(_output.path_join("ui-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("UI REPORT ", JSON.stringify(report))
	print("UI TESTS PASS" if failures.is_empty() else "UI TESTS FAIL")
	if not failures.is_empty():
		get_tree().quit(1)
