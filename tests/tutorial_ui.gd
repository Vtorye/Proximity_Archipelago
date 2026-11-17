extends "res://tests/ui_runner.gd"
## A complete first chapter through the real screen, build palette, recruitment and travel.
var _chapter: FirstChapter
var _boat: CargoShip

func _run() -> void:
	Engine.time_scale = 6.0
	seed(20261118)
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await _navigation()
	AppSettings.language = "ru"
	AppSettings.text_size = AppSettings.TYPOGRAPHY.minimum_sizes.size() - 1
	AppSettings.apply()
	await click(Router._current.controls[&"tutorial"])
	await _navigation()
	screen = Router._current
	_chapter = screen.chapter
	expect(screen.world.population.count() == 15, "the authored colony starts with three inhabited nests")
	expect(screen.world.queen != null and screen.world.chapter_rules != null, "the queen and chapter rules are authored in the scene")
	expect(not screen.hud.get_node("%Timer").visible and not screen.hud.colony_summary.get_node("%Totals").visible, "the first scenes hide the execution clock and stock totals")
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.FOOD, "the introduction leads to a real meal demonstration")
	await _until_stage(FirstChapter.Stage.FREE_BUILD)
	await _capture("01-developed-colony")
	expect(screen.world.build_controller.placement_allowed.is_valid(), "the chapter owns player action restrictions")
	screen._inspect_building(Vector2i(24, 25))
	expect(screen.nest_popup == null, "nest details remain hidden before the economy reveal")
	await _build(&"statue", Vector2i(27, 24))
	await _wait_wishes(1)
	await _build(&"road", Vector2i(22, 24))
	await _wait_building(Vector2i(22, 24), true)
	expect(_chapter.wish_index == 1, "an optional road is tracked without counting as a building wish")
	await _build(&"sawmill", Vector2i(21, 22))
	await _wait_wishes(2)
	await _build(&"quarry", Vector2i(29, 21))
	await _until_stage(FirstChapter.Stage.PLANNER)
	await _capture("02-planner")
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.DEMOLITION, "the planner starts demolition before the execution")
	expect(screen.save_game("user://demolition.save") == OK, "demolition progress can be saved")
	await _reload("user://demolition.save")
	await _until_stage(FirstChapter.Stage.EXECUTION)
	expect(screen.world.registry.at(Vector2i(27, 24)) == null, "the player's statue is removed")
	expect((screen.world.registry.at(Vector2i(21, 22)) as Workplace).improvement == null, "the player's sawmill upgrade is removed")
	expect((screen.world.registry.at(Vector2i(29, 21)) as Workplace).improvement == null, "the player's quarry upgrade is removed")
	expect(screen.world.map.surface_at(Vector2i(22, 24)).kind != TerrainType.Kind.ROAD, "the player's optional road is removed")
	expect(screen.world.registry.at(Vector2i(19, 21)) != null and screen.world.population.count() == 15, "original infrastructure and residents survive the planner")
	await _capture("03-execution")
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.WORK and screen.hud.colony_summary.get_node("%Totals").visible, "the execution reveals supplies and real work")
	await _until_stage(FirstChapter.Stage.RECRUIT)
	await _capture("04-logistics-and-recruitment")
	screen._focus_chapter_cell(Vector2i(24, 25))
	await frames(2)
	await click_at(cell_point(Vector2i(24, 25)))
	var nest: NestMenu = screen.nest_popup
	if nest == null:
		expect(false, "the nest window opens for the recruitment lesson")
		get_tree().quit(1)
		return
	await click(nest.controls[&"residents"])
	var buy: Button = nest.controls[&"buy_worker"]
	if buy == null:
		expect(false, "the worker recruitment button is exposed")
		get_tree().quit(1)
		return
	await click(buy)
	await frames(2)
	await key(KEY_ESCAPE)
	await _until_stage(FirstChapter.Stage.SUPPLIES)
	expect(screen.world.population.count() >= 21, "recruitment and the queen's new base add residents")
	expect(screen.world.registry.at(_chapter.rules.magic_cell) is House, "the queen creates a real crown-funded nest")
	await _until_stage(FirstChapter.Stage.ATTACK)
	await _dialogue()
	expect(screen.world.combat.spiders.size() == _chapter.rules.spider_count, "the invasion begins once after preparation")
	expect(not screen.world.combat.automatic_waves, "the first island uses authored invasion points")
	expect(not _chapter.can_evacuate(), "evacuation cannot start without a ship and loaded cargo")
	await _capture("05-invasion")
	await _build(&"ship", _chapter.rules.ship_cell)
	await _wait_building(_chapter.rules.ship_cell)
	_boat = _chapter.ship()
	expect(_boat != null and not screen.world.voyage.departed, "a completed ship does not finish the island")
	expect(_boat.manifest.is_empty() or not _boat.supplied(), "cargo is delivered physically after ship construction")
	await _build_roads()
	var saved_cargo := false
	for frame in range(18000):
		await frames(1)
		_boat = _chapter.ship()
		if not saved_cargo and _boat != null and not _boat.manifest.is_empty() and not _boat.supplied():
			saved_cargo = true
			expect(screen.save_game("user://loading.save") == OK, "the loading phase saves")
			await _reload("user://loading.save")
			_boat = _chapter.ship()
			expect(screen.world.logistics.cargo_receiver == _boat, "loading restores its receiver")
		if _chapter.can_evacuate():
			break
	expect(saved_cargo and _chapter.can_evacuate(), "carriers resume loading and make evacuation possible")
	if not _chapter.can_evacuate():
		print("CHAPTER STALLED ", _chapter.status_text(), " ants ", screen.world.population.count())
		get_tree().quit(1)
		return
	expect(_boat.manifest.values().all(func(amount): return int(amount) <= 100), "each resource stays within ship capacity")
	await _capture("06-ship-and-cargo")
	await click(screen.chapter_panel.get_node("%Evacuate"))
	expect(_chapter.stage == FirstChapter.Stage.ESCORT and screen.world.queen.walking, "the evacuation button starts the queen's road journey")
	await frames(15)
	expect(screen.save_game("user://escort.save") == OK, "the moving queen saves")
	await _reload("user://escort.save")
	expect(screen.world.queen.walking and _chapter.stage == FirstChapter.Stage.ESCORT, "the queen resumes her saved journey")
	await _until_stage(FirstChapter.Stage.FAREWELL)
	await _capture("07-farewell")
	await _dialogue()
	for frame in range(180):
		await frames(1)
		if screen.world.voyage.departed:
			break
	expect(screen.world.voyage.departed and _chapter.stage == FirstChapter.Stage.COMPLETE, "arrival and the ending unlock travel")
	expect(screen.world.voyage.travelling_characters.has("Worker") and screen.world.voyage.travelling_characters.has("Courier"), "both companions board")
	var manifest: Dictionary = screen.world.voyage.departure_manifest.duplicate()
	expect(manifest.values().all(func(amount): return int(amount) >= 50 and int(amount) <= 100), "the next island receives bounded loaded supplies")
	await frames(4)
	await click(screen.campaign_panel.get_node("%Destination1"))
	await _navigation()
	screen = Router._current
	expect(screen.world.voyage.island == 2 and not screen._chapter_active, "the normal second island opens")
	for id in manifest:
		expect(screen.world.inventory.quantity(screen.world.inventory.type_by_id(StringName(id))) <= int(manifest[id]), "travel carries cargo instead of abandoned colony wealth")
	print("FIRST CHAPTER UI ", assertions, " assertions, ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)

func _navigation() -> void:
	await frames(8)
	for frame in range(180):
		if not Router.is_navigating() and Router.current_screen_key() != &"":
			await frames(6)
			return
		await frames(1)

func _dialogue() -> void:
	for index in range(140):
		if not screen.story.is_modal:
			return
		var entry: LineEdit = screen.story.get_node("%NameInput")
		if screen.story.get_node("%NameWindow").visible:
			entry.text = "A"
			entry.text_changed.emit(entry.text)
			await frames(5)
		else:
			await click(screen.story.get_node("%Continue"))
	expect(false, "dialogue returns control")

func _until_stage(expected: FirstChapter.Stage) -> void:
	for frame in range(18000):
		if _chapter.stage == expected:
			return
		if screen.story.is_modal:
			await _dialogue()
		await frames(1)
	expect(false, "chapter reaches stage " + FirstChapter.Stage.keys()[expected])
	print("STALLED ", _chapter.stage, " ", _chapter.status_text())
	get_tree().quit(1)

func _wait_wishes(count: int) -> void:
	for frame in range(6000):
		if _chapter.wish_index >= count:
			return
		await frames(1)
	expect(false, "a physical building completes its wish")

func _wait_building(cell: Vector2i, road := false) -> void:
	for frame in range(6000):
		if screen.world.construction_service.at(cell, road) == null:
			if road or screen.world.registry.at(cell) is CargoShip:
				return
		await frames(1)
	expect(false, "the physical site completes")

func _build(id: StringName, cell: Vector2i) -> void:
	if screen._section != &"build" or screen._construction == null:
		await key(KEY_B)
	var menu: ConstructionMenu = screen._construction
	if menu == null:
		expect(false, "build opens for " + str(id))
		return
	screen._focus_chapter_cell(cell)
	await frames(2)
	await choose_building(menu, id)
	# Moving the palette camera leaves a free map point between the top goals and bottom strip.
	await click_at(cell_point(cell))
	expect(menu.draft.size() > 0, "the player draws " + str(id))
	if menu.draft.size() == 0:
		print("BUILD FAILED ", id, " ", cell, " screen ", cell_point(cell), " reason ", menu.draft.last_result.code, " obstacles ", screen._construction_obstacles())
		return
	await click(menu.controls[&"apply"])

func _build_roads() -> void:
	for cell in _chapter.rules.route_cells:
		if screen.world.map.surface_at(cell).kind != TerrainType.Kind.ROAD:
			await _build(&"road", cell)
			await _wait_building(cell, true)

func _reload(path: String) -> void:
	var saved := SessionSave.read(path)
	expect(not saved.is_empty(), "the chapter snapshot validates")
	if saved.is_empty():
		var file := FileAccess.open(path, FileAccess.READ)
		file.seek(32)
		var raw: Dictionary = bytes_to_var(file.get_buffer(file.get_length() - 32))
		var probe := LevelLayout.create_world(raw.layout)
		print("SAVE PROBE world=", probe, " shape=", SessionSave._valid_shape(raw), " objects=", raw.layout.objects)
		if probe != null:
			probe.free()
		get_tree().quit(1)
		return
	var layout: Dictionary = saved.layout.duplicate()
	layout["snapshot"] = saved
	Router.goto(&"match", layout)
	await _navigation()
	screen = Router._current
	_chapter = screen.chapter

func _capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await capture(label, 1)
