extends "res://tests/ui_runner.gd"
## A complete first chapter through the real screen, build palette, recruitment and travel.
var _chapter: FirstChapter
var _boat: CargoShip
var _seen_lines: Array[String] = []

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
	expect(not screen.hud.get_node("%Timer").visible and screen.hud.colony_summary.get_node("%Totals").visible, "the tutorial uses the real resource HUD without an execution timer")
	expect(not screen.world.queen.visible, "the queen has no sprite on the map")
	expect(screen.get_node_or_null("Interface/ChapterPanel") == null, "the separate tutorial interface is removed")
	expect(screen.hud.get_node("%TasksTab").visible and screen.hud.get_node("%ColonyTab").visible, "the standard task and colony tabs are present")
	expect(not screen.world.inventory.quantities_known and screen.hud.colony_summary.get_node("%Totals").get_parsed_text().contains("∞"), "materials appear infinite before the planner arrives")
	await _window_controls(screen.story.get_node("%DialogueHeader"), Vector2(0, -20))
	await _capture("00-dialogue-window")
	await _dialogue()
	await _practice_controls()
	expect(_chapter.stage == FirstChapter.Stage.ROAD, "the original road dialogue leads to a mandatory road task")
	await _window_controls(screen.story.get_node("%HintHeader"), Vector2(-198, 40))
	await frames(30)
	expect(_chapter.stage == FirstChapter.Stage.ROAD, "waiting alone cannot complete the road task")
	await _build(&"road", _chapter.rules.road_cell)
	await _wait_building(_chapter.rules.road_cell, true)
	await frames(2)
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.ROYAL_ORDER, "the completed road unlocks the first royal request")
	await click(screen.hud.get_node("%TasksTab"))
	var category: Button = screen.hud.task_panel.get_node("%Category")
	if not category.button_pressed:
		await click(category)
	var first_request: TaskRequest = screen.hud.task_panel.get_node("%Requests").get_child(0)
	expect(first_request.task == _chapter.rules.opening_order, "the same real task cards contain the opening order")
	var first_id: StringName = &"feast" if "--opening=feast" in OS.get_cmdline_user_args() else &"statue"
	var first_offer: TaskOffer = first_request.get_node("%Offers").get_child(0 if first_id == &"feast" else 1)
	await _capture("00-first-order")
	await click(first_offer.placement)
	await click_at(cell_point(_chapter.rules.order_cell))
	expect(screen._construction.draft.size() == 1, "the first task has a drawn construction plan")
	await click(screen._construction.controls[&"apply"])
	await _until_stage(FirstChapter.Stage.SECOND_ORDER)
	expect(_seen_lines.has("ui.story.tutorial.feast") == (first_id == &"feast") and _seen_lines.has("ui.story.tutorial.statue") == (first_id == &"statue"), "the original reaction matches the first completed building")
	expect(_seen_lines.has("ui.chapter.feast_expires") == (first_id == &"feast") and _seen_lines.has("ui.chapter.statue_blocks") == (first_id == &"statue"), "the first explanation only discusses the building just completed")
	expect(screen.save_game("user://second-order.save") == OK, "the first royal choice saves")
	await _reload("user://second-order.save")
	var second_id: StringName = &"statue" if first_id == &"feast" else &"feast"
	expect(_chapter._first_choice == first_id, "the second order remembers the first choice after loading")
	for variant in _chapter.rules.followup_order.variants:
		expect(_chapter.allows_order(_chapter.rules.followup_order.id, variant.id) == (variant.building.id == second_id), "the second task requires the opposite building")
	await _order(_chapter.rules.followup_order, second_id, _chapter.rules.followup_cell)
	await _until_stage(FirstChapter.Stage.WORKER_ADVICE)
	expect(_seen_lines.has("ui.story.tutorial.feast") and _seen_lines.has("ui.story.tutorial.statue") and _seen_lines.has("ui.story.tutorial.farewell"), "both original building reactions and the original farewell survive the two orders")
	await frames(30)
	expect(_chapter.stage == FirstChapter.Stage.WORKER_ADVICE, "the player must speak to the worker before improving buildings")
	await _talk_to(&"Worker")
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.FREE_BUILD, "the worker explains i and unlocks the improvement task")
	expect(not screen.world.build_controller.options.has(_chapter.rules.wishes[0]), "statues are offered through Tasks, not the build catalog")
	await _capture("01-developed-colony")
	expect(screen.world.build_controller.placement_allowed.is_valid(), "the chapter owns player action restrictions")
	screen._inspect_building(Vector2i(24, 25))
	expect(screen.nest_popup != null, "the standard nest window works in the tutorial")
	await key(KEY_ESCAPE)
	await _build(&"road", Vector2i(22, 24))
	await _wait_building(Vector2i(22, 24), true)
	expect(_chapter.wish_index == 1, "an optional road is tracked without counting as a building wish")
	await _build(&"sawmill", Vector2i(21, 22))
	await _wait_wishes(2)
	await _build(&"quarry", Vector2i(29, 21))
	await _until_stage(FirstChapter.Stage.PLANNER)
	expect(screen.world.inventory.quantities_known and not screen.hud.colony_summary.get_node("%Totals").get_parsed_text().contains("∞"), "the planner reveals the finite material stocks")
	for limit in _chapter.rules.revealed_supplies:
		expect(screen.world.inventory.available(limit.type) <= limit.amount, "the revealed stock is scarce")
	await _capture("02-planner")
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.DEMOLITION, "the planner starts demolition before the execution")
	var pending_demolition := _chapter.created.size()
	await frames(30)
	expect(_chapter.stage == FirstChapter.Stage.DEMOLITION and _chapter.created.size() == pending_demolition, "the planner waits for the player instead of demolishing automatically")
	expect(not _chapter.allows_placement(null, Vector2i(24, 25)), "original infrastructure cannot be demolished during the lesson")
	expect(screen.save_game("user://demolition.save") == OK, "demolition progress can be saved")
	await _reload("user://demolition.save")
	await _demolition_lesson()
	await _until_stage(FirstChapter.Stage.EXECUTION)
	expect(screen.world.registry.at(Vector2i(27, 24)) == null, "the player's statue is removed")
	expect((screen.world.registry.at(Vector2i(21, 22)) as Workplace).improvement == null, "the player's sawmill upgrade is removed")
	expect((screen.world.registry.at(Vector2i(29, 21)) as Workplace).improvement == null, "the player's quarry upgrade is removed")
	expect(screen.world.map.surface_at(Vector2i(22, 24)).kind != TerrainType.Kind.ROAD, "the player's optional road is removed")
	expect(screen.world.registry.at(Vector2i(19, 21)) != null and screen.world.population.count() == 15, "original infrastructure and residents survive the planner")
	await _capture("03-execution")
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.WORK, "the worker lesson requires the player to rebuild a sawmill")
	await frames(30)
	expect(_chapter.stage == FirstChapter.Stage.WORK, "watching autonomous ants cannot complete the building task")
	await _build(&"sawmill", Vector2i(21, 22))
	await _until_stage(FirstChapter.Stage.TRANSPORT)
	await _dialogue()
	expect(not _chapter._transport_requested, "the courier does not place the player's delivery order")
	var depot := _chapter._demonstration_depot()
	screen._focus_chapter_cell(depot.cell)
	await frames(2)
	await click_at(cell_point(depot.cell))
	await click(screen.nest_popup.controls[&"orders"])
	var once: SpinBox = screen.nest_popup._order_rows["wood"].spins.once
	expect(once.min_value < 0, "one-time orders support a negative range")
	once.value = -6
	expect(_chapter._transport_requested and _chapter._transport_delivered == 0, "setting minus six starts the separate waiting step")
	expect(_chapter.status_text() == tr("ui.chapter.wait_export"), "the hint changes from editing the order to waiting for delivery")
	await key(KEY_ESCAPE)
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
	await _until_stage(FirstChapter.Stage.MAGIC)
	await _build(&"base_nest", _chapter.rules.magic_cell)
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
	screen._focus_chapter_cell(_chapter.rules.ship_cell)
	await frames(2)
	await click_at(cell_point(_chapter.rules.ship_cell))
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

func _practice_controls() -> void:
	expect(_chapter.stage == FirstChapter.Stage.PAUSE_LESSON and not screen.story.get_node("%PortraitMount").visible, "the queen disappears while the player practices pause")
	await frames(20)
	expect(_chapter.stage == FirstChapter.Stage.PAUSE_LESSON, "the pause lesson waits for real input")
	await key(KEY_SPACE)
	expect(PauseController.is_manually_paused() and not screen.story.is_modal, "space actually pauses the simulation")
	await _capture("00-pause-practice")
	await click(screen.hud.controls[&"pause"])
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.CAMERA_LESSON and not screen.story.is_modal, "resuming unlocks camera practice")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(450, 180)
	press.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	get_viewport().push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(500, 180)
	motion.relative = Vector2(50, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	get_viewport().push_input(motion, true)
	press.pressed = false
	press.position = motion.position
	press.button_mask = 0
	get_viewport().push_input(press, true)
	await frames(2)
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.ZOOM_LESSON, "dragging the map unlocks zoom practice")
	await frames(20)
	expect(_chapter.stage == FirstChapter.Stage.ZOOM_LESSON, "the zoom lesson waits for actual zoom input")
	await click(screen.hud.controls[&"zoom_out"])
	await frames(2)
	await _dialogue()
	expect(_chapter.stage == FirstChapter.Stage.TALK_LESSON, "Shuti asks who can explain roads")
	await click(screen.hud.controls[&"talk"])
	expect(screen.conversations.visible, "Talk opens from the real bottom bar")
	await _capture("00-conversations")
	for button: Button in screen.conversations.get_node("%People").get_children():
		if (button.get_meta(&"character") as StoryCharacter).id == &"Courier":
			await click(button)
			break
	expect(screen.story.is_modal, "the player selects the courier to ask about road construction")
	await _dialogue()

func _talk_to(character_id: StringName) -> void:
	await click(screen.hud.controls[&"talk"])
	for button: Button in screen.conversations.get_node("%People").get_children():
		if (button.get_meta(&"character") as StoryCharacter).id == character_id:
			await click(button)
			return
	expect(false, "the requested character is present in Talk")

func _order(task: TaskSpec, building_id: StringName, cell: Vector2i) -> void:
	await click(screen.hud.get_node("%TasksTab"))
	var category: Button = screen.hud.task_panel.get_node("%Category")
	if not category.button_pressed:
		await click(category)
	for request: TaskRequest in screen.hud.task_panel.get_node("%Requests").get_children():
		if request.task != task:
			continue
		for offer: TaskOffer in request.get_node("%Offers").get_children():
			if offer.order.variant.building.id == building_id:
				await click(offer.placement)
				screen._focus_chapter_cell(cell)
				await frames(2)
				await click_at(cell_point(cell))
				expect(screen._construction.draft.size() == 1, "the second task has a drawn construction plan")
				await click(screen._construction.controls[&"apply"])
				return
	expect(false, "the follow-up order appears in Tasks")

func _window_controls(header: WindowHeader, movement: Vector2) -> void:
	if header.action == WindowHeader.Action.FOLD:
		await click(header.toggle)
		expect(header.collapsed and not header.body.visible, "the window folds through its title bar")
		await click(header.toggle)
		expect(not header.collapsed and header.body.visible, "the window reopens without losing its contents")
	var before := header.panel.position
	var point := header.handle.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + movement
	motion.relative = movement
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	press.pressed = false
	press.position = motion.position
	press.button_mask = 0
	get_viewport().push_input(press, true)
	await frames(4)
	expect(not header.panel.position.is_equal_approx(before), "dragging the title moves the window")
	var moved := header.panel.position
	header.queue_layout()
	await frames(3)
	expect(header.panel.position.is_equal_approx(moved), "window layout preserves its dragged position")

func _dialogue() -> void:
	for index in range(140):
		if not screen.story.is_modal:
			return
		if screen.story._line != null:
			_seen_lines.append(screen.story._line.text)
		var entry: LineEdit = screen.story.get_node("%NameInput")
		if screen.story.get_node("%NameWindow").visible:
			entry.text = "A"
			entry.text_changed.emit(entry.text)
			await frames(5)
		else:
			await click(screen.story.get_node("%Continue"))
	expect(false, "dialogue returns control")

func _until_stage(expected: FirstChapter.Stage) -> void:
	print("WAITING FOR ", FirstChapter.Stage.keys()[expected], " from ", FirstChapter.Stage.keys()[_chapter.stage])
	for frame in range(18000):
		if _chapter.stage == expected:
			return
		if screen.story.is_modal:
			await _dialogue()
		await frames(1)
	expect(false, "chapter reaches stage " + FirstChapter.Stage.keys()[expected])
	print("STALLED ", _chapter.stage, " ", _chapter.status_text())
	print("DELIVERY ", _chapter._transport_requested, " ", _chapter._transport_delivered)
	for depot in screen.world.logistics.nests():
		print("DEPOT ", depot.cell, " filled ", screen.world.inventory.depot_fill(screen.world.logistics.store_of(depot)), " wood ", screen.world.inventory.stock_of(screen.world.logistics.store_of(depot), screen.world.inventory.type_by_id(&"wood")), " requests ", depot.requests)
	get_tree().quit(1)

func _wait_wishes(count: int) -> void:
	for frame in range(6000):
		if _chapter.wish_index >= count:
			return
		await frames(1)
	expect(false, "a physical building completes its wish")

func _demolition_lesson() -> void:
	var hint: WindowHeader = screen.story.get_node("%HintHeader")
	if not hint.collapsed:
		await click(hint.toggle)
	for index in range(8):
		if _chapter.stage != FirstChapter.Stage.DEMOLITION:
			return
		var cell: Vector2i = _chapter.created.front().cell
		await key(KEY_B)
		var menu: ConstructionMenu = screen._construction
		await click(menu.controls[&"demolish"])
		screen._focus_chapter_cell(cell)
		await frames(2)
		await click_at(cell_point(cell))
		expect(menu.draft.size() == 1, "the player marks the highlighted structure for demolition")
		await click(menu.controls[&"apply"])
		await frames(3)
	expect(false, "manual demolition reaches the execution")

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
