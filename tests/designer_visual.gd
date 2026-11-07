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
	expect(menu.controls.has(&"base_nest") and menu.controls[&"base_nest"].cost_label.text == "1 Знак колонии", "the palette offers a separate base nest priced in crowns")
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
	await _check_paused_navigation()
	await _check_storage_and_hover()
	screen.world.population.agents()[0].speed = 30.0
	await key(KEY_N)
	expect(screen.navigation_overlay.reference_speed == 30.0, "diagnostic times follow the actual reference ant speed")
	await key(KEY_N)
	await key(KEY_N)
	Router.goto(&"main_menu")
	await frames(40)
	await _check_saved_map()
	_finish()

func _check_paused_navigation() -> void:
	var routes: Button = screen.hud.controls[&"routes"]
	var settings: Button = screen.hud.controls[&"settings"]
	AppSettings.ui_scale = AppSettings.MAX_UI_SCALE
	AppSettings.apply()
	await frames(3)
	for caption_key in ["ui.hud.routes", "ui.hud.routes_cells", "ui.hud.routes_priority"]:
		expect(routes.text == caption_key and routes.atr(routes.text) != caption_key, "each navigation mode shows a translated caption")
		expect(routes.get_parent() == settings.get_parent() and get_viewport().get_visible_rect().encloses(settings.get_global_rect()), "full-size top bar fits the route caption next to settings")
		await key(KEY_N)
	AppSettings.reset_defaults()
	await frames(3)
	await key(KEY_SPACE)
	var construction := Router.top_overlay() as ConstructionMenu
	var time: float = screen.world.match_controller.time_remaining
	var ant: AntAgent = screen.world.population.agents()[0]
	var satiety: float = ant.needs.satiety
	await key(KEY_N)
	expect(get_tree().paused and screen.navigation_overlay.mode == 1 and screen.hud.navigation_panel.visible, "N opens the cell view during construction")
	await click(routes)
	var origin := Vector2i(26, 25)
	await click_at(cell_point(origin), MOUSE_BUTTON_RIGHT)
	expect(screen.navigation_overlay.mode == 2 and screen.navigation_overlay.origin == origin and screen.selection.selected, "the header button opens priorities and right click selects an origin during construction")
	var draft_cell := Vector2i(27, 25)
	await click_at(cell_point(draft_cell))
	expect(construction.draft.size() == 1, "priority view leaves construction painting available")
	await click_at(cell_point(draft_cell), MOUSE_BUTTON_RIGHT)
	expect(construction.draft.size() == 0 and screen.navigation_overlay.origin == origin, "right click still undoes a draft placement before selecting an origin")
	expect(screen.world.match_controller.time_remaining == time and ant.needs.satiety == satiety, "navigation during construction keeps time and hunger frozen")
	await capture("02b-navigation-during-construction")
	await key(KEY_N)
	await key(KEY_SPACE)
	await click(settings)
	var pause := Router.top_overlay() as PauseMenu
	time = screen.world.match_controller.time_remaining
	await key(KEY_N)
	await click(routes)
	expect(pause != null and Router.top_overlay() == pause and get_tree().paused and screen.navigation_overlay.mode == 2, "N and the top bar button both work with the pause menu open")
	expect(screen.world.match_controller.time_remaining == time, "the pause menu keeps the timer frozen while cycling views")
	await capture("02c-navigation-during-pause")
	await click(pause.controls[&"settings"])
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 2, "settings keep their modal keyboard boundary")
	await key(KEY_ESCAPE)
	await key(KEY_N)
	await click(pause.controls[&"resume"])
	expect(screen.navigation_overlay.mode == 0 and not get_tree().paused, "view stays selected when resuming the game")

func _check_storage_and_hover() -> void:
	var hud: MatchHud = screen.hud
	var panel: NavigationPanel = hud.navigation_panel
	var workplace: Workplace = screen.world.get_node("Workplace2")
	await click(hud.controls[&"settings"])
	var pause := Router.top_overlay() as PauseMenu
	var move := InputEventMouseMotion.new()
	move.position = cell_point(workplace.cell)
	get_viewport().push_input(move, true)
	await frames(10)
	expect(get_tree().paused and screen.navigation_overlay.mode == 0 and panel.visible and panel._detail.text.contains(" / 4"), "hovering an unselected workplace shows its load during pause")
	await capture("02d-workplace-hover-paused")
	await click(pause.controls[&"resume"])
	var cell := Vector2i(27, 27)
	var nest: BuildOption = load("res://game/building/options/house.tres")
	expect(screen.world.build_controller.try_build(nest, cell), "fixture builds a small warehouse")
	var depot: House = screen.world.registry.at(cell) as House
	await click_at(cell_point(cell))
	var menu := Router.top_overlay() as NestMenu
	expect(menu != null and menu.house == depot and menu._inventory_tab.visible and menu._dispatch_hint.visible and menu._capacity.text.contains("0 / 100"), "click opens a warehouse window with its inventory and dispatch settings")
	await click(menu._dispatch)
	expect(not depot.auto_dispatch, "the depot auto-dispatch toggle updates this nest")
	expect(menu._dispatch_hint.text == "ui.nest.dispatch_hint", "local inventory explains that carriers collect at any fill level")
	await capture("02e-small-nest-settings")
	await click(menu.controls[&"residents"])
	expect(menu._role_labels[AntAgent.Role.WORKER].text == "Рабочие · 4" and menu._role_labels[AntAgent.Role.CARRIER].text == "Носильщики · 1", "the residents tab counts roles assigned to this small nest")
	expect(menu.controls[&"buy_worker"].disabled and menu._population.text.contains("5 / 5"), "a full small nest disables recruitment")
	await capture("02f-small-nest-residents")
	await key(KEY_ESCAPE)
	expect(not Router.has_overlay() and not get_tree().paused, "closing the nest window resumes the match")
	var main: House = screen.world.logistics.main_nest
	await click_at(cell_point(main.cell))
	menu = Router.top_overlay() as NestMenu
	expect(menu != null and menu.house == main and not menu._dispatch.visible, "the main nest shows unlimited storage")
	await click(menu.controls[&"residents"])
	var food: ResourceType = screen.world.inventory.type_by_id(&"food")
	screen.world.inventory.add(food, 100)
	var before: int = screen.world.inventory.quantity(food)
	await click(menu.controls[&"buy_worker"])
	await click(menu.controls[&"buy_carrier"])
	expect(main.residents.size() == 7 and screen.world.inventory.quantity(food) == before - 13 and menu._population.text.contains("7 / 20"), "recruiting both roles charges the configured prices and updates the population")
	await click(menu.controls[&"kill_worker"])
	await click(menu.controls[&"kill_carrier"])
	expect(main.residents.size() == 5 and menu._role_labels[AntAgent.Role.WORKER].text == "Рабочие · 4" and menu._role_labels[AntAgent.Role.CARRIER].text == "Носильщики · 1", "kill buttons remove one selected role and refresh its count")
	await capture("02g-main-nest-recruitment")
	await click(menu.controls[&"kill_carrier"])
	expect(menu.controls[&"kill_carrier"].disabled, "the kill button is disabled when this nest has no carriers")
	await click(menu.controls[&"buy_carrier"])
	expect(main.residents.size() == 5 and not menu.controls[&"kill_carrier"].disabled, "recruiting reuses the freed resident slot")
	var prior_scale: float = AppSettings.ui_scale
	for scale in [AppSettings.MIN_UI_SCALE, AppSettings.MAX_UI_SCALE]:
		AppSettings.ui_scale = scale
		AppSettings.apply()
		await frames(3)
		expect(get_viewport().get_visible_rect().encloses(menu.controls[&"close"].get_global_rect()) and get_viewport().get_visible_rect().encloses(menu.controls[&"kill_carrier"].get_global_rect()), "the nest window fits the supported UI scale")
	AppSettings.ui_scale = prior_scale
	AppSettings.apply()
	await key(KEY_ESCAPE)
	await _check_new_base(depot)

func _check_new_base(barracks: House) -> void:
	var world: World = screen.world
	world.units.process_mode = Node.PROCESS_MODE_DISABLED
	world.inventory.add(world.inventory.type_by_id(&"royal"), 1)
	var option: BuildOption = load("res://game/building/options/base_nest.tres")
	var cell := Vector2i(29, 27)
	for candidate in [Vector2i(29, 27), Vector2i(28, 27), Vector2i(28, 28)]:
		if world.build_controller.check(option, candidate).allowed():
			cell = candidate
			break
	await key(KEY_SPACE)
	var construction := Router.top_overlay() as ConstructionMenu
	await click(construction.controls[&"base_nest"])
	await click_at(cell_point(cell))
	expect(construction.draft.size() == 1, "a player can plan a base nest from its own palette button")
	await capture("02h-base-nest-construction")
	await key(KEY_SPACE)
	var base := world.registry.at(cell) as House
	expect(base != null and base.is_main_nest and base.resident_limit() == 20, "applying the plan creates a base nest with twenty resident slots")
	if base == null:
		world.units.process_mode = Node.PROCESS_MODE_INHERIT
		return
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	world.logistics.deposit(base, [_entry(wood, 7)])
	await click_at(cell_point(cell))
	var menu := Router.top_overlay() as NestMenu
	expect(menu != null and menu.house == base and not menu._dispatch.visible and menu._stock_labels[wood.id].text == "Древесина · 7", "the new base window shows its own inventory and hides barracks dispatch controls")
	await capture("02i-built-base-inventory")
	await click(menu.controls[&"residents"])
	expect(menu._population.text.contains("5 / 20") and not menu.controls[&"buy_worker"].disabled, "a built base can recruit beyond the barracks limit")
	await capture("02j-built-base-residents")
	await key(KEY_ESCAPE)
	expect((barracks.get_node("Sprite") as Sprite2D).modulate != (base.get_node("Sprite") as Sprite2D).modulate, "the world distinguishes barracks and base sprites")
	await capture("02k-base-and-barracks")
	world.units.process_mode = Node.PROCESS_MODE_INHERIT

func _entry(type: ResourceType, count: int) -> ResourceAmount:
	var amount := ResourceAmount.new()
	amount.type = type
	amount.amount = count
	return amount

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
	var canteen_cell := Vector2i(28, 26)
	await click_at(_editor_point(editor, canteen_cell), MOUSE_BUTTON_RIGHT)
	expect(editor._object_at(canteen_cell) == null and editor._map.get_cell_source_id(canteen_cell) != -1, "editor removes the only canteen and keeps its terrain")
	var coast_cell := Vector2i(25, 23)
	var coast: int = editor._brushes.find(Vector4i(4, 0, 0, 0))
	expect(coast >= 0 and editor._brush.get_item_text(coast) == tr("ui.terrain.coast"), "the sixteen-pixel coast tile is available as an editor brush")
	editor._brush.select(coast)
	await click_at(_editor_point(editor, coast_cell))
	expect(editor._map.get_cell_source_id(coast_cell) == 4, "the coast brush paints authored terrain")
	var base_brush: int = editor._brushes.find("build/base_nest")
	var barracks_brush: int = editor._brushes.find("Home")
	expect(base_brush >= 0 and barracks_brush >= 0 and editor._brush.get_item_text(barracks_brush) == "Казарма", "the editor offers separate base and barracks brushes")
	var extra_base_cell := Vector2i(28, 28)
	editor._brush.select(base_brush)
	await click_at(_editor_point(editor, extra_base_cell))
	expect(editor._object_at(extra_base_cell) is House and editor._object_at(extra_base_cell).is_main_nest, "the base brush paints a typed base nest")
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
	expect(Router.current_screen_key() == &"match", "saved map without a canteen launches as a match")
	if Router.current_screen_key() != &"match":
		Router.goto(&"main_menu")
		await frames(40)
		return
	screen = Router._current
	expect(screen.world.registry.canteens().is_empty(), "the saved match keeps the canteen removed")
	expect((screen.world.registry.at(extra_base_cell) as House).is_main_nest, "the authored additional base survives save and launch")
	expect(is_equal_approx(screen.world.route_service.entry_cost(coast_cell), 1.2), "the authored coast keeps its distinct movement cost after saving and loading")
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
