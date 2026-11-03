extends "res://tests/ui_runner.gd"
func _run() -> void:
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(40)
	await click(Router._current.controls[&"play"])
	await frames(40)
	screen = Router._current
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 1, "N shows milliseconds per cell")
	await capture("01-entry-milliseconds", 30)
	await _check_full_map_overlay()
	await key(KEY_N)
	await click_at(cell_point(Vector2i(26, 25)), MOUSE_BUTTON_RIGHT)
	expect(screen.navigation_overlay.origin == Vector2i(26, 25), "right click picks the distance origin")
	await _check_camera_controls()
	await capture("02-distance-and-job-scores", 30)
	await key(KEY_SPACE)
	var menu: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	expect(menu.controls[&"house"].cost_label.text == "10 Древесина + 20 Камень", "menu shows the configured composite nest price")
	await capture("03-configured-house-price", 30)
	var path := "res://game/building/options/house.tres"
	var original := FileAccess.get_file_as_string(path)
	await frames(65)
	FileAccess.open(path, FileAccess.WRITE).store_string(original.replace("amount = 10", "amount = 15"))
	await frames(90)
	expect(menu.controls[&"house"].cost_label.text == "15 Древесина + 20 Камень", "saved configuration edits update an already open menu")
	await capture("04-live-price-reload", 30)
	FileAccess.open(path, FileAccess.WRITE).store_string(original)
	await frames(65)
	await key(KEY_SPACE)
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 0, "third N restores the ordinary map")
	expect(screen.hud.theme.get_stylebox("panel", "PanelContainer").texture == load("res://game/assets/ui/panel.svg"), "ordinary HUD transparency returns when navigation is hidden")
	screen.world.population.agents()[0].speed = 30.0
	await key(KEY_N)
	expect(screen.navigation_overlay.reference_speed == 30.0, "diagnostic times follow the actual reference ant speed")
	await key(KEY_N)
	await key(KEY_N)
	Router.goto(&"main_menu")
	await frames(40)
	await _check_saved_map()
	_finish()

func _check_full_map_overlay() -> void:
	var header: Control = screen.hud.controls[&"settings"].get_parent().get_parent()
	var regions: Array[Rect2] = [header.get_global_rect(), screen.hud.task_panel.get_global_rect(), screen.hud.navigation_panel.get_global_rect(), screen.hud._bottom.get_global_rect()]
	var probes: Array[Vector2] = []
	for region in regions:
		for cell in screen.world.route_service.snapshot().walkable_cells():
			var map: TileMapLayer = screen.world.get_node("Map")
			var size: Vector2 = Vector2(map.tile_set.tile_size) * map.get_global_transform_with_canvas().get_scale()
			var area := Rect2(cell_point(cell) - size / 2 + Vector2(2, 2), size - Vector2(4, 4))
			var overlap: Rect2 = area.intersection(region.grow(-2))
			if overlap.size.x >= 3 and overlap.size.y >= 3:
				probes.append(overlap.position + Vector2.ONE)
				break
	expect(probes.size() == regions.size(), "land probes cover the header, task board, legend and footer")
	var process: int = screen.world.units.process_mode
	screen.world.units.process_mode = Node.PROCESS_MODE_DISABLED
	screen.hud.hide()
	screen.navigation_overlay.mode = 0
	screen.navigation_overlay.queue_redraw()
	await frames(3)
	await RenderingServer.frame_post_draw
	var baseline: Image = get_viewport().get_texture().get_image()
	screen.navigation_overlay.mode = 1
	screen.navigation_overlay.queue_redraw()
	await frames(3)
	await RenderingServer.frame_post_draw
	var overlay: Image = get_viewport().get_texture().get_image()
	var factor: Vector2 = Vector2(overlay.get_size()) / get_viewport().get_visible_rect().size
	for point in probes:
		var a: Color = baseline.get_pixelv(Vector2i(point * factor))
		var b: Color = overlay.get_pixelv(Vector2i(point * factor))
		expect(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1, "world overlay continues underneath UI regions")
	await capture("01b-unbroken-world-overlay", 20)
	screen.hud.show()
	screen.world.units.process_mode = process

func _check_camera_controls() -> void:
	var origin: Vector2i = screen.navigation_overlay.origin
	var position: Vector2 = screen.camera.position
	var level: int = screen.camera.level
	await click_at(cell_point(Vector2i(27, 26)))
	expect(screen.navigation_overlay.origin == origin, "left click leaves the navigation origin unchanged")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(360, 250)
	get_viewport().push_input(press, true)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(392, 266)
	drag.relative = Vector2(32, 16)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(drag, true)
	press.pressed = false
	press.position = drag.position
	get_viewport().push_input(press, true)
	await frames(4)
	expect(screen.camera.position != position and screen.navigation_overlay.origin == origin, "left drag pans the map while navigation remains active")
	for code in [KEY_RIGHT, KEY_LEFT, KEY_UP, KEY_DOWN]:
		await _hold_arrow(code)
	screen.camera.set_level(4)
	await _hold_arrow(KEY_RIGHT)
	screen.camera.set_level(level)
	screen.camera.position = position
	screen.camera.force_update_scroll()
	await click_at(screen.hud.task_panel.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	expect(screen.navigation_overlay.origin == origin and not Router.has_overlay(), "right clicks on UI never select a cell behind it")

func _hold_arrow(code: Key) -> void:
	var position: Vector2 = screen.camera.position
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(8)
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)
	var offset: Vector2 = screen.camera.position - position
	var expected := Vector2.RIGHT if code == KEY_RIGHT else (Vector2.LEFT if code == KEY_LEFT else (Vector2.UP if code == KEY_UP else Vector2.DOWN))
	expect(offset.dot(expected) > 0.01, "arrow key pans in the expected direction at the current zoom")

func _check_saved_map() -> void:
	await click(Router._current.controls[&"maps"])
	await frames(40)
	var editor: Control = Router._current
	expect(Router.current_screen_key() == &"level_editor", "Maps opens the level editor")
	var original := Vector2i(21, 22)
	var destination := Vector2i(22, 23)
	var road := Vector4i(3, 2, 0, 0)
	editor._brush.select(editor._brushes.find(road))
	await click_at(_editor_point(editor, destination))
	editor._brush.select(0)
	await click_at(_editor_point(editor, original))
	await click_at(_editor_point(editor, destination) + Vector2(3, 4))
	var workplace: Building = editor._object_at(destination)
	expect(workplace is Workplace and editor._object_at(original) == null, "move tool relocates the authored workplace")
	expect(workplace.global_position.is_equal_approx(editor._map.to_global(editor._map.map_to_local(destination))), "workplaces snap to the center of the destination tile")
	expect(editor._map.get_cell_atlas_coords(destination) == Vector2i(2, 0), "terrain and workplace can share the edited cell")
	await capture("05-level-editor")
	var title: String = "Map check %d %d" % [OS.get_process_id(), Time.get_ticks_usec()]
	editor._title.text = title
	await click(_editor_button(editor, "ui.map.save"))
	var filename: String = title.sha256_text() + ".json"
	expect(not LevelStore.load_level(filename).is_empty(), "edited layout is persisted to disk")
	await click(_editor_button(editor, "ui.common.main_menu"))
	await frames(40)
	await click(Router._current.controls[&"maps"])
	await frames(40)
	editor = Router._current
	for index in range(editor._saved.item_count):
		if editor._saved.get_item_metadata(index) == filename:
			editor._saved.select(index)
			break
	await click(_editor_button(editor, "ui.map.load"))
	expect(editor._title.text == title and editor._object_at(destination) is Workplace and editor._map.get_cell_atlas_coords(destination) == Vector2i(2, 0), "a fresh editor loads the saved tiles and objects")
	await click(_editor_button(editor, "ui.menu.play"))
	await frames(50)
	DirAccess.remove_absolute(LevelStore.DIRECTORY.path_join(filename))
	expect(Router.current_screen_key() == &"match", "saved map launches as a match")
	if Router.current_screen_key() != &"match":
		Router.goto(&"main_menu")
		await frames(40)
		return
	screen = Router._current
	expect(screen.world.registry.at(destination) is Workplace and screen.world.route_service.entry_cost(destination) < 1.0, "match uses the saved placement and terrain for navigation")
	await capture("06-saved-map-in-play")
	await click(screen.hud.controls[&"settings"])
	await click(Router.top_overlay().controls[&"restart"])
	await frames(50)
	screen = Router._current
	expect(screen.world.registry.at(destination) is Workplace, "restart keeps the selected map")
	Router.goto(&"main_menu")
	await frames(40)

func _editor_point(editor: Control, cell: Vector2i) -> Vector2:
	return editor._map.get_global_transform_with_canvas() * editor._map.map_to_local(cell)

func _editor_button(editor: Control, label: String) -> Button:
	for button in editor.find_children("*", "Button", true, false):
		if button.text == label:
			return button
	return null
