extends "res://tests/ui_runner.gd"
## Real pointer input checks paused painting, undo, budgets, batch commit, and cancellation.

func _run() -> void:
	seed(20261025)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	await _check_tutorial_and_backdrop()
	open_fixed_match()
	await frames(45)
	screen = Router._current
	use_immediate_construction_fixture(screen.world)
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
	use_immediate_construction_fixture(screen.world)
	expect(not is_instance_valid(retired) and not get_tree().paused and not Router.has_overlay(), "pause restart removes the previous world and every pause reason")
	expect(screen.world.population.count() == 5 and screen.world.match_controller.time_remaining > 178.0, "pause restart begins a fresh three-minute colony")
	var world: World = screen.world
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var food: ResourceType = world.inventory.type_by_id(&"food")
	# Only this fixture changes a price and funds it; shipped definitions keep their balance.
	var nest: SceneBuildOption = load("res://game/building/options/barracks.tres").duplicate(true)
	nest.costs = [_entry(stone, 5), _entry(food, 20)]
	world.build_controller.unlock_option(nest, world.build_controller.options[2])
	world.inventory.add(food, 10)
	screen.camera.position = Vector2(400, 464)
	screen.camera.force_update_scroll()
	await frames(2)
	var revision: int = world.route_service.revision
	var stock: int = world.inventory.quantity(wood)
	await click(screen.hud.controls[&"build"])
	var menu: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	expect(menu != null and get_tree().paused, "construction mode pauses the simulation")
	await _validate_palette(menu)
	await choose_building(menu, &"house")
	expect((menu.get_node("%Price") as Label).text.contains("5 %s + 20 %s" % [TranslationServer.translate("ui.resource.stone"), TranslationServer.translate("ui.resource.food")]), "details show both components of an editable price")
	await capture("03-bottom-palette-and-composite-price")
	await choose_building(menu, &"road")
	var time: float = world.match_controller.time_remaining
	var satiety: float = world.population.agents()[0].needs.satiety
	await _stroke(Vector2i(23, 28), Vector2i(29, 28))
	expect(menu.draft.size() == 7 and menu._cost.text.contains(("7 %s" % TranslationServer.translate("ui.resource.wood"))), "one fast drag fills every road cell and totals its price")
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
	await choose_building(menu, &"house")
	await click_at(cell_point(Vector2i(29, 27)))
	expect(menu.draft.size() == 8 and not menu.controls[&"apply"].disabled, "road and nest share an affordable plan")
	expect(menu._cost.text.contains(("7 %s" % TranslationServer.translate("ui.resource.wood"))) and menu._cost.text.contains(("5 %s" % TranslationServer.translate("ui.resource.stone"))) and menu._cost.text.contains(("20 %s" % TranslationServer.translate("ui.resource.food"))), "plan total includes every resource across all placements")
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
	world.build_controller.unlock_option(expensive, world.build_controller.options[0])
	await key(KEY_B)
	menu = Router.top_overlay() as ConstructionMenu
	await click_at(cell_point(Vector2i(30, 28)))
	expect(menu.draft.size() == 1 and menu.controls[&"apply"].disabled and menu._status.text == (TranslationServer.translate("ui.placement.resources")), "unaffordable draft explains its budget and blocks continuation")
	await capture("07-unaffordable-plan")
	await key(KEY_ESCAPE)
	expect(Router.top_overlay() == menu and get_tree().paused, "Esc cannot partly commit an unaffordable draft")
	await click(menu.controls[&"cancel"])
	await key(KEY_B)
	menu = Router.top_overlay() as ConstructionMenu
	await choose_building(menu, &"apple_tree")
	await click_at(cell_point(Vector2i(29, 27)))
	expect(menu.draft.size() == 0 and menu._status.text == (TranslationServer.translate("ui.placement.occupied")), "occupied cells explain why the brush cannot paint")
	await capture("08-occupied-cell-feedback")
	var camera_before: Vector2 = screen.camera.position
	await _pan()
	expect(screen.camera.position != camera_before and menu.draft.size() == 0, "middle drag pans while construction remains paused")
	await key(KEY_ESCAPE)
	expect(get_tree().paused and Router.top_overlay() == menu, "Escape folds planning without resuming")
	await key(KEY_SPACE)
	await _check_requested_features()
	await _check_text_sizes()
	Router.goto(&"main_menu")
	await frames(45)
	AppSettings.reset_defaults()
	_finish()

func _check_text_sizes() -> void:
	await click(screen.hud.controls[&"settings"])
	await click(Router.top_overlay().controls[&"settings"])
	var settings: Control = Router.top_overlay()
	var original: Vector2i = get_window().size
	for step in range(2):
		await click(settings.controls[&"text_size_plus"])
	var large: Button = settings.controls[&"text_size_plus"]
	expect(AppSettings.text_size == 2 and large.disabled, "largest text size is available")
	expect(get_window().size == original, "changing text size preserves the window")
	await capture("09-settings-text-18")
	await click(settings.controls[&"done"])
	await click(Router.top_overlay().controls[&"resume"])
	await key(KEY_B)
	await _validate_palette(Router.top_overlay() as ConstructionMenu)
	await capture("10-construction-text-18")
	await key(KEY_SPACE)
	AppSettings.text_size = 0
	AppSettings.save()
	await key(KEY_B)
	await _validate_palette(Router.top_overlay() as ConstructionMenu)
	await capture("12-construction-text-14")
	await key(KEY_SPACE)

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
	var viewport: Rect2 = get_viewport().get_visible_rect()
	expect(viewport.encloses(menu.panel.get_global_rect()), "construction panel fits")
	for id in [&"move", &"demolish", &"undo", &"cancel", &"apply"]:
		expect(menu.panel.get_global_rect().encloses(menu.controls[id].get_global_rect()), "construction actions fit")
	var header: WindowHeader = menu.get_node("%PaletteHeader")
	var unfolded: float = menu.panel.size.y
	expect(not header.draggable and menu.category_buttons.size() >= 3, "construction is docked and categorized")
	await click(header.toggle)
	expect(header.collapsed and menu.panel.size.y < unfolded, "construction folds to its header")
	await click(header.toggle)
	expect(not header.collapsed, "construction unfolds again")

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
	expect(count >= 3 and count <= int(18 * factor * factor), "scaled menu icon renders its three pixel dots")
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
	await click(Router._current.controls[&"play"])
	await click(Router._current.get_node("%Add"))
	await click(Router._current.get_node("%Start"))
	await frames(45)
	expect(Router.current_screen_key() == &"match" and Router._current._chapter_active, "the new campaign opens the first chapter")
	Router.goto(&"main_menu")
	await frames(35)


func _check_requested_features() -> void:
	var world: World = screen.world
	var road: TileBuildOption = load("res://game/building/options/road.tres")
	world.build_controller.unlock_option(road, world.build_controller.options[0])
	await key(KEY_SPACE)
	var menu: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	expect(menu != null and get_tree().paused and not screen.hud.controls.has(&"pause"), "Space opens construction without a separate HUD pause button")
	var cell := Vector2i(30, 28)
	await click_at(cell_point(cell))
	await choose_building(menu, &"house")
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
