extends "res://tests/ui_runner.gd"
## Real pointer input checks paused painting, undo, budgets, batch commit, and cancellation.

func _run() -> void:
	seed(20261025)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	await _check_tutorial_and_backdrop()
	await click(Router._current.controls[&"play"])
	await frames(45)
	screen = Router._current
	for id in screen.hud.stock_chips:
		var icon: TextureRect = screen.hud.stock_chips[id].get_child(0)
		print("RESOURCE ICON ", id, " ", icon.get_global_rect(), " MIN ", icon.custom_minimum_size, " SCALE ", icon.scale)
	expect(screen.world.map_size == Vector2i(50, 50) and screen.camera.bounds.size == Vector2(800, 800), "gameplay and camera both use the fifty-cell map")
	screen.camera.set_level(0)
	screen.camera.pan(Vector2(100000, 100000))
	expect(screen.camera.position == Vector2(400, 360), "zoomed-out camera centers a narrower map and clamps its top edge")
	screen.camera.pan(Vector2(-100000, -100000))
	expect(screen.camera.position == Vector2(400, 440), "zoomed-out camera clamps its bottom edge")
	screen.camera.pan((screen.camera.position - screen.camera.bounds.get_center()) * screen.camera.zoom)
	await capture("00-smaller-map-overview")
	screen.camera.set_level(2)
	var image: Image = await capture("01-centered-menu-dots")
	_check_dots(image, screen.hud.controls[&"settings"])
	await click(screen.hud.controls[&"settings"])
	await capture("02-pause-restart-button")
	var retired: World = screen.world
	await click(Router.top_overlay().controls[&"restart"])
	await frames(45)
	screen = Router._current
	expect(not is_instance_valid(retired) and not get_tree().paused and not Router.has_overlay(), "pause restart removes the previous world and every pause reason")
	expect(screen.world.population.count() == 5 and screen.world.match_controller.time_remaining > 178.0, "pause restart begins a fresh three-minute colony")
	var world: World = screen.world
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var food: ResourceType = world.inventory.type_by_id(&"food")
	# Only this fixture changes a price and funds it; shipped definitions keep their balance.
	var nest: SceneBuildOption = load("res://game/building/options/house.tres").duplicate(true)
	nest.costs = [_entry(stone, 5), _entry(food, 20)]
	world.build_controller.options[2] = nest
	world.inventory.add(food, 10)
	screen.camera.position = Vector2(400, 464)
	screen.camera.force_update_scroll()
	await frames(2)
	var revision: int = world.route_service.revision
	var stock: int = world.inventory.quantity(wood)
	await click(screen.hud.controls[&"build"])
	var menu: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	expect(menu != null and get_tree().paused, "construction mode pauses the simulation")
	_validate_palette(menu)
	expect((menu.controls[&"house"] as BuildChoiceButton).cost_label.text == "5 Камень + 20 Пища", "palette shows both components of an editable price")
	await capture("03-bottom-palette-and-composite-price")
	var time: float = world.match_controller.time_remaining
	var satiety: float = world.population.agents()[0].needs.satiety
	await _stroke(Vector2i(23, 28), Vector2i(29, 28))
	expect(menu.draft.size() == 7 and menu._cost.text.contains("7 Древесина"), "one fast drag fills every road cell and totals its price")
	expect(world.route_service.revision == revision and world.inventory.quantity(wood) == stock, "draft leaves navigation and inventory unchanged")
	expect(world.match_controller.time_remaining == time and world.population.agents()[0].needs.satiety == satiety, "painting pauses both the timer and hunger")
	await capture("04-road-stroke-preview")
	await click(menu.controls[&"undo"])
	expect(menu.draft.size() == 0 and menu.controls[&"undo"].disabled, "undo removes the whole drag")
	await _stroke(Vector2i(23, 28), Vector2i(29, 28))
	await click(menu.controls[&"cancel"])
	expect(not get_tree().paused and not Router.has_overlay() and world.route_service.revision == revision and world.inventory.quantity(wood) == stock, "cancel discards the complete plan for free")
	await key(KEY_B)
	menu = Router.top_overlay() as ConstructionMenu
	expect(menu != null and get_tree().paused, "B opens the same construction editor")
	await _stroke(Vector2i(23, 28), Vector2i(29, 28))
	await click(menu.controls[&"house"])
	await click_at(cell_point(Vector2i(29, 27)))
	expect(menu.draft.size() == 8 and not menu.controls[&"apply"].disabled, "road and nest share an affordable plan")
	expect(menu._cost.text.contains("7 Древесина") and menu._cost.text.contains("5 Камень") and menu._cost.text.contains("20 Пища"), "plan total includes every resource across all placements")
	expect(world.population.count() == 5 and world.registry.at(Vector2i(29, 27)) == null, "draft nest has no residents or world occupancy before commit")
	await capture("05-composite-plan-total")
	var food_before: int = world.inventory.quantity(food)
	var stone_before: int = world.inventory.quantity(stone)
	await click(screen.hud.controls[&"settings"])
	await click(Router.top_overlay().controls[&"settings"])
	expect(Router.top_overlay() != menu and not menu.visible and get_tree().paused, "settings open above the paused draft")
	await key(KEY_ESCAPE)
	await click(Router.top_overlay().controls[&"resume"])
	expect(Router.top_overlay() == menu and menu.draft.size() == 8 and get_tree().paused, "closing settings restores the draft and its pause")
	await key(KEY_SPACE)
	expect(not Router.has_overlay() and not get_tree().paused and world.route_service.revision == revision + 1, "unpausing applies the entire draft with one navigation revision")
	expect(world.population.count() == 10 and world.registry.at(Vector2i(29, 27)) is House, "committed nest creates its residents")
	expect(world.inventory.quantity(wood) == stock - 7 and world.inventory.quantity(stone) == stone_before - 5 and world.inventory.quantity(food) == food_before - 20, "commit charges the composite total exactly once")
	for x in range(23, 30):
		expect(world.build_controller.map.get_cell_atlas_coords(Vector2i(x, 28)) == Vector2i(2, 0), "every previewed road cell is committed")
	await capture("06-applied-road-and-nest")
	var expensive: TileBuildOption = world.build_controller.options[0].duplicate(true)
	expensive.costs = [_entry(wood, 10000)]
	world.build_controller.options[0] = expensive
	await key(KEY_B)
	menu = Router.top_overlay() as ConstructionMenu
	await click_at(cell_point(Vector2i(30, 28)))
	expect(menu.draft.size() == 1 and menu.controls[&"apply"].disabled and menu._status.text == "Не хватает свободных ресурсов", "unaffordable draft explains its budget and blocks continuation")
	await capture("07-unaffordable-plan")
	await key(KEY_ESCAPE)
	expect(Router.top_overlay() == menu and get_tree().paused, "Esc cannot partly commit an unaffordable draft")
	await click(menu.controls[&"cancel"])
	await key(KEY_B)
	menu = Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"apple_tree"])
	await click_at(cell_point(Vector2i(29, 27)))
	expect(menu.draft.size() == 0 and menu._status.text == "Сначала снесите существующее здание", "occupied cells explain why the brush cannot paint")
	await capture("08-occupied-cell-feedback")
	var camera_before: Vector2 = screen.camera.position
	await _pan()
	expect(screen.camera.position != camera_before and menu.draft.size() == 0, "middle drag pans while construction remains paused")
	await key(KEY_ESCAPE)
	expect(not get_tree().paused and not Router.has_overlay(), "empty draft resumes safely with Esc")
	await _check_requested_features()
	await _check_ui_scales()
	Router.goto(&"main_menu")
	await frames(45)
	AppSettings.reset_defaults()
	_finish()

func _check_ui_scales() -> void:
	await click(screen.hud.controls[&"settings"])
	await click(Router.top_overlay().controls[&"settings"])
	var settings: Control = Router.top_overlay()
	expect(AppSettings.ui_scale == 0.75 and settings._scale_value.text == "75%", "interface starts smaller at seventy-five percent")
	var window_before: Vector2i = get_window().size
	await click(settings.controls[&"ui_scale_plus"])
	expect(get_window().size == window_before, "UI scale changes preserve the physical window size")
	expect(AppSettings.ui_scale == 1.0 and settings.controls[&"ui_scale_plus"].disabled, "settings apply the largest supported UI scale immediately")
	expect(get_viewport().get_visible_rect().encloses(settings.controls[&"done"].get_global_rect()), "largest settings scale keeps its close action visible")
	await capture("09-settings-scale-100")
	preload("res://tests/pixel_font_checks.gd").verify(self, settings)
	await click(settings.controls[&"done"])
	await click(Router.top_overlay().controls[&"resume"])
	await key(KEY_B)
	var menu: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	_validate_palette(menu)
	await capture("10-toolbar-scale-100")
	await key(KEY_ESCAPE)
	await click(screen.hud.controls[&"settings"])
	await click(Router.top_overlay().controls[&"settings"])
	settings = Router.top_overlay()
	window_before = get_window().size
	await click(settings.controls[&"ui_scale_minus"])
	await click(settings.controls[&"ui_scale_minus"])
	expect(get_window().size == window_before, "shrinking UI preserves the physical window size")
	expect(AppSettings.ui_scale == 0.5 and settings.controls[&"ui_scale_minus"].disabled, "settings apply the smallest supported UI scale immediately")
	var config := ConfigFile.new()
	expect(config.load(AppSettings.PATH) == OK and config.get_value("interface", "scale", 0.0) == 0.5, "UI scale persists in the settings file")
	await capture("11-settings-scale-50")
	preload("res://tests/pixel_font_checks.gd").verify(self, settings)
	await click(settings.controls[&"done"])
	await click(Router.top_overlay().controls[&"resume"])
	await key(KEY_B)
	menu = Router.top_overlay() as ConstructionMenu
	_validate_palette(menu)
	await capture("12-toolbar-scale-50")
	await key(KEY_ESCAPE)
	await click(screen.hud.controls[&"settings"])
	await click(Router.top_overlay().controls[&"restart"])
	await frames(45)
	screen = Router._current
	expect(AppSettings.ui_scale == 0.5 and screen.hud.controls[&"settings"].custom_minimum_size == Vector2(16, 16), "match restart preserves the selected interface scale")

func _entry(type: ResourceType, amount: int) -> ResourceAmount:
	var result := ResourceAmount.new()
	result.type = type
	result.amount = amount
	return result

func _stroke(first: Vector2i, last: Vector2i) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = cell_point(first)
	get_viewport().push_input(press, true)
	await frames(2)
	var move := InputEventMouseMotion.new()
	move.position = cell_point(last)
	move.relative = move.position - press.position
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move, true)
	await frames(3)
	press.pressed = false
	press.button_mask = 0
	press.position = move.position
	get_viewport().push_input(press, true)
	await frames(3)

func _pan() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	press.position = Vector2(320, 180)
	get_viewport().push_input(press, true)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(340, 180)
	move.relative = Vector2(20, 0)
	move.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	get_viewport().push_input(move, true)
	press.pressed = false
	press.position = move.position
	get_viewport().push_input(press, true)
	await frames(3)

func _validate_palette(menu: ConstructionMenu) -> void:
	preload("res://tests/pixel_font_checks.gd").verify(self, menu)
	print("PALETTE ", menu.panel.get_global_rect(), " MIN ", menu.panel.get_combined_minimum_size())
	expect(get_viewport().get_visible_rect().encloses(menu.panel.get_global_rect()), "construction palette fits the viewport")
	expect(menu.panel.get_global_rect().size.y <= get_viewport().get_visible_rect().size.y * 0.22, "compact palette occupies less than a quarter of the screen height")
	for id in [&"road", &"ground", &"house", &"apple_tree", &"move", &"demolish", &"undo", &"cancel", &"apply"]:
		expect(menu.panel.get_global_rect().encloses(menu.controls[id].get_global_rect()), "every construction action fits the bottom palette")

func _check_dots(image: Image, button: Button) -> void:
	var factor: float = floorf(minf(float(image.get_width()) / 640.0, float(image.get_height()) / 360.0))
	var offset: Vector2 = (Vector2(image.get_size()) - Vector2(640, 360) * factor) / 2.0
	var center: Vector2 = button.get_global_rect().get_center() * factor + offset
	var total := Vector2.ZERO
	var count := 0
	for y in range(int(center.y - 6 * factor), int(center.y + 6 * factor)):
		for x in range(int(center.x - 8 * factor), int(center.x + 8 * factor)):
			var color: Color = image.get_pixel(x, y)
			if color.r > 0.75 and color.g > 0.7 and color.b > 0.55:
				total += Vector2(x + 0.5, y + 0.5)
				count += 1
	expect(count >= 3 and count <= int(18 * factor * factor * AppSettings.ui_scale), "scaled menu icon renders its three pixel dots")
	print("DOT CENTERS ", center, " ", total / maxf(1, count), " PIXELS ", count)
	expect(count > 0 and (total / maxf(1, count)).distance_to(center) <= factor * 0.75, "menu dots stay centered at the chosen interface scale")

func _check_tutorial_and_backdrop() -> void:
	var backdrop: ColonyBackdrop
	# UiScale may precede the backdrop; discover the actual presentation node.
	for child in Router._current.get_children():
		if child is ColonyBackdrop: backdrop = child
	expect(backdrop != null, "main menu owns its animated road backdrop")
	if backdrop != null:
		var center := Vector2(floorf(backdrop.size.x / 64.0), floorf(backdrop.size.y / 64.0)) * 32.0 + Vector2(16, 16)
		for index in range(28):
			var point: Vector2 = backdrop.ant_position(index)
			expect(absf(point.y - center.y) <= 4.0 if index % 2 == 0 else absf(point.x - center.x) <= 4.0, "title ant stays inside its visible road lane")
	await capture("13-main-menu-road-lanes")
	await click(Router._current.controls[&"tutorial"])
	await frames(35)
	expect(Router.current_screen_key() == &"tutorial" and not get_tree().paused, "tutorial opens as an independent screen")
	for page in range(4):
		var tutorial: Control = Router._current
		expect(tutorial._page == page and not tutorial._body.text.is_empty(), "tutorial displays the requested instruction page")
		expect(get_viewport().get_visible_rect().encloses(tutorial._body.get_global_rect()), "tutorial text fits the viewport")
		preload("res://tests/pixel_font_checks.gd").verify(self, tutorial)
		await capture("14-tutorial-%d" % page)
		if page < 3: await click(tutorial.controls[&"next"])
	await click(Router._current.controls[&"previous"])
	expect(Router._current._page == 2, "tutorial supports paging backwards")
	for factor in [0.5, 1.0]:
		AppSettings.ui_scale = factor
		AppSettings.apply()
		await frames(5)
		for page in range(4):
			Router._current._show_page(page)
			await frames(3)
			expect(get_viewport().get_visible_rect().encloses(Router._current._body.get_global_rect()), "tutorial remains readable at the smallest and largest interface scale")
			expect(Router._current._body.get_visible_line_count() == Router._current._body.get_line_count(), "tutorial never clips instruction lines")
		await capture("14-tutorial-scale-%d" % roundi(factor * 100))
	AppSettings.ui_scale = 0.75
	AppSettings.apply()
	await frames(3)
	await click(Router._current.controls[&"back"])
	await frames(35)
	expect(Router.current_screen_key() == &"main_menu", "tutorial menu button returns to the title screen")
	await click(Router._current.controls[&"tutorial"])
	await frames(35)
	await key(KEY_ESCAPE)
	await frames(35)
	expect(Router.current_screen_key() == &"main_menu", "Escape returns from tutorial to the main menu")
	await click(Router._current.controls[&"tutorial"])
	await frames(35)
	await click(Router._current.controls[&"play"])
	await frames(45)
	expect(Router.current_screen_key() == &"match", "tutorial play button starts a real colony")
	Router.goto(&"main_menu")
	await frames(35)

func _check_requested_features() -> void:
	var world: World = screen.world
	var road: TileBuildOption = load("res://game/building/options/road.tres")
	world.build_controller.options[0] = road
	await key(KEY_SPACE)
	var menu: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	expect(menu != null and get_tree().paused and not screen.hud.controls.has(&"pause"), "Space opens construction without a separate HUD pause button")
	var cell := Vector2i(30, 28)
	await click_at(cell_point(cell))
	await click(menu.controls[&"house"])
	await click_at(cell_point(cell))
	expect(menu.draft.size() == 2, "real clicks stack a road and nest on one cell")
	await capture("15-layered-road-and-nest")
	await click_at(cell_point(cell), MOUSE_BUTTON_RIGHT)
	expect(menu.draft.size() == 1 and menu.draft.commands()[0].option is TileBuildOption, "right click removes the most recent building and retains its road")
	await click_at(cell_point(cell), MOUSE_BUTTON_RIGHT)
	expect(menu.draft.size() == 0 and Router.top_overlay() == menu, "second right click removes the remaining layer without closing construction")
	await click(menu.controls[&"undo"])
	expect(menu.draft.size() == 1, "toolbar undo restores a right-click removal")
	await click(menu.controls[&"move"])
	var before: Vector2 = screen.camera.position
	await _stroke(Vector2i(23, 28), Vector2i(25, 28))
	expect(screen.camera.position != before and menu.draft.size() == 1, "move tool pans with held left mouse without painting")
	var level: int = screen.camera.level
	await click_at(Vector2(330, 180), MOUSE_BUTTON_WHEEL_UP)
	expect(screen.camera.level == level + 1 and menu.draft.size() == 1, "wheel zoom works during paused construction without changing the draft")
	await click_at(Vector2(330, 180), MOUSE_BUTTON_WHEEL_DOWN)
	await capture("16-move-tool-and-zoom")
	await click(menu.controls[&"cancel"])
	# New residents were created at 29:27 by the earlier composite-price fixture.
	screen.camera.position = Vector2(400, 464)
	screen.camera.force_update_scroll()
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"demolish"])
	var nest_cell := Vector2i(29, 27)
	var house: House = world.registry.at(nest_cell) as House
	var count: int = world.population.count()
	await click_at(cell_point(nest_cell))
	expect(menu.draft.size() == 1 and world.registry.at(nest_cell) == house, "demolition button marks a nest without deleting it")
	await capture("17-planned-demolition")
	await click_at(cell_point(nest_cell), MOUSE_BUTTON_RIGHT)
	expect(menu.draft.size() == 0 and world.population.count() == count, "right click cancels a demolition mark without killing residents")
	await click_at(cell_point(nest_cell))
	await key(KEY_SPACE)
	expect(menu._confirmation.visible and Router.top_overlay() == menu and world.population.count() == count, "unpause requests explicit confirmation before destroying residents")
	await capture("18-demolition-confirmation")
	await click(menu.controls[&"keep_residents"])
	expect(not menu._confirmation.visible and world.registry.at(nest_cell) == house, "declining demolition keeps residents and the editable draft")
	await key(KEY_SPACE)
	await click(menu.controls[&"confirm_demolish"])
	expect(not Router.has_overlay() and not get_tree().paused and not is_instance_valid(house) and world.population.count() == count - 5, "confirmed demolition removes the nest and resumes the simulation")
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"demolish"])
	await click_at(cell_point(Vector2i(29, 28)))
	expect(menu.draft.size() == 1, "demolition tool stages a committed road as soil")
	await key(KEY_SPACE)
	expect(world.build_controller.map.get_cell_atlas_coords(Vector2i(29, 28)) == Vector2i(1, 0), "road demolition commits when construction resumes")
	await capture("19-demolition-applied")
