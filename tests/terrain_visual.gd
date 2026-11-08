extends "res://tests/ui_runner.gd"
## Real editor and construction input; a compact fixture makes all five ground types readable together.
func _run() -> void:
	seed(20261108)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	await click(Router._current.controls[&"maps"])
	await frames(15)
	var editor: Control = Router._current
	var found := false
	for index in range(editor._saved.item_count):
		if editor._saved.get_item_metadata(index) == "builtin/five_soils":
			editor._saved.select(index)
			found = true
	expect(found, "the bundled soil map appears in the ordinary map picker")
	await click(_button(editor, "ui.map.load"))
	editor._camera.set_level(WorldCamera.MIN_LEVEL)
	expect(editor._title.text == "Пять земель", "the five-soil archipelago loads as an editable painted map")
	for source in range(5, 10):
		expect(editor._brushes.has(Vector4i(source, 0, 0, 0)), "the editor exposes each soil as a normal tile brush")
	await capture("01-five-soil-archipelago", 25)
	await click(_button(editor, "ui.terrain.generate"))
	expect(editor._dirty and editor._status.text.contains("Почвы распределены"), "the soil generator explicitly edits the map instead of replacing it during play")
	await capture("02-editor-soil-distribution", 20)
	Router.goto(&"match", _fixture())
	await frames(25)
	screen = Router._current
	var world: World = screen.world
	world.units.process_mode = Node.PROCESS_MODE_DISABLED
	await capture("03-readable-soil-fixture", 20)
	var dry := Vector2i(8, 3)
	var rocky := Vector2i(5, 3)
	var sand := Vector2i(14, 3)
	await key(KEY_SPACE)
	var menu := Router.top_overlay() as ConstructionMenu
	_focus(dry)
	await click(menu.controls[&"house"])
	await hover(dry)
	expect(menu.controls[&"house"].cost_label.text == "7 Древесина + 14 Камень", "the live palette shows the discounted nest price at the hovered dry tile")
	await click_at(cell_point(dry))
	expect(menu._cost.text.contains("7 Древесина + 14 Камень"), "the plan total agrees with the cell-specific palette price")
	await capture("04-dry-soil-discount", 20)
	await click(menu.controls[&"cancel"])
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	_focus(rocky)
	await click(menu.controls[&"road"])
	await click_at(cell_point(rocky))
	expect(menu.draft.size() == 0 and menu._status.text == tr("ui.placement.soil_restricted"), "rocky ground rejects roads with visible soil-specific feedback")
	await capture("05-rocky-soil-restriction", 20)
	await click(menu.controls[&"cancel"])
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	_focus(sand)
	await click(menu.controls[&"road"])
	await hover(sand)
	expect(menu.controls[&"road"].cost_label.text == "2 Древесина", "sand road pricing is visible before painting")
	await click_at(cell_point(sand))
	await capture("06-sand-road-price", 20)
	await click(menu.controls[&"cancel"])
	_focus(Vector2i(3, 2))
	await click_at(cell_point(Vector2i(3, 2)), MOUSE_BUTTON_RIGHT)
	expect(screen.hud.navigation_panel._detail.text.contains("150%"), "a fertile berry source explains its production modifier")
	await capture("07-fertile-berry-inspector", 20)
	_focus(Vector2i(9, 2))
	await click_at(cell_point(Vector2i(9, 2)), MOUSE_BUTTON_RIGHT)
	expect(screen.hud.navigation_panel._detail.text.contains("75%"), "a dry berry source explains its lower production")
	await capture("08-dry-berry-inspector", 20)
	_focus(world.logistics.main_nest.cell)
	await click_at(cell_point(world.logistics.main_nest.cell))
	var nest := Router.top_overlay() as NestMenu
	await click(nest.controls[&"residents"])
	expect(nest._population.text.contains("5 / 25") and nest._population.tooltip_text.contains("25%"), "the nest window explains extra capacity from adjacent wet ground")
	await capture("09-wet-ground-nest-capacity", 25)
	await key(KEY_ESCAPE)
	world.units.process_mode = Node.PROCESS_MODE_INHERIT
	var building_cell := Vector2i(10, 4)
	_focus(building_cell)
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"house"])
	await click_at(cell_point(building_cell))
	await key(KEY_SPACE)
	var site: ConstructionSite = world.build_controller.construction.at(building_cell)
	expect(site != null and world.inventory.quantity(world.inventory.type_by_id(&"wood")) == 53 and world.inventory.quantity(world.inventory.type_by_id(&"stone")) == 26, "applying the dry-soil plan earmarks exactly seven wood and fourteen stone")
	await capture("10-discounted-material-delivery", 20)
	for second in range(55):
		if world.registry.at(building_cell) is House: break
		await frames(30)
	var barracks := world.registry.at(building_cell) as House
	expect(barracks != null and barracks.resident_limit() == 6 and world.population.count() == 10, "real delivery and assembly open a discounted barracks with the adjacent wet-soil capacity bonus")
	await capture("11-completed-soil-aware-barracks", 30)
	await frames(300)
	await click_at(cell_point(Vector2i(9, 2)), MOUSE_BUTTON_RIGHT)
	await capture("12-working-colony-on-soils", 30)
	_focus(Vector2i(17, 9))
	await click_at(cell_point(Vector2i(17, 9)), MOUSE_BUTTON_RIGHT)
	await frames(8)
	expect(screen.hud.navigation_panel._detail.text.contains(tr("ui.terrain.impassable")), "water still displays impassability rather than an infinite movement time")
	await capture("13-water-is-impassable", 20)
	Router.goto(&"main_menu")
	await frames(25)
	_finish()

func _focus(cell: Vector2i) -> void:
	screen.camera.position = screen.world.route_service.cell_to_world(cell)
	screen.camera.force_update_scroll()

func _button(editor: Control, text: String) -> Button:
	for button in editor.find_children("*", "Button", true, false):
		if button.text == text: return button
	return null

func _fixture() -> Dictionary:
	var tiles: Array = []
	for x in range(18):
		for y in range(10):
			var source: int = 5 + clampi((x - 2) / 3, 0, 4) if x >= 2 and x <= 16 else 3
			tiles.append([x, y, source, 0, 0, 0])
	tiles[tiles.size() - 1] = [17, 9, 3, 3, 0, 0]
	return {"version": 1, "tiles": tiles, "objects": [[10, 6, "build/base_nest"], [10, 7, "Food"], [3, 2, "AppleTree"], [9, 2, "AppleTree"]]}

func hover(cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = cell_point(cell)
	event.global_position = event.position
	get_viewport().push_input(event, true)
	await frames(6)
