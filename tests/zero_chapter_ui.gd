extends "res://tests/tutorial_ui.gd"
## Covers the new campaign entry point and the physical shipments and builds it teaches.

var _zero_chapter: ZeroChapter
var _rules: ZeroChapterRules

func _run() -> void:
	Engine.time_scale = 6.0
	seed(20261118)
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await _navigation()
	AppSettings.language = "ru"
	AppSettings.apply()
	await click(Router._current.controls[&"play"])
	await click(Router._current.get_node("%Add"))
	var skip := "--skip" in OS.get_cmdline_user_args()
	if skip:
		await click(Router._current.get_node("%SkipLessons"))
	await click(Router._current.get_node("%Start"))
	await _navigation()
	screen = Router._current
	_chapter = screen.chapter
	_zero_chapter = _chapter as ZeroChapter
	if _zero_chapter == null:
		print("ZERO UI FAIL new campaign does not open the zero chapter")
		get_tree().quit(1)
		return
	_rules = _chapter.rules as ZeroChapterRules
	if not skip:
		await _run_lessons()
		if not failures.is_empty():
			_finish_zero()
			return
	expect(_zero_chapter.phase == ZeroChapter.Phase.PREPARATION, "campaign reaches the timed task")
	expect(screen.hud.get_node("%Timer").visible, "the active countdown is visible")
	expect(screen.world.registry.at(_rules.stone_cell) == null, "the old outcrop is gone")
	expect(screen.world.registry.at(_rules.finite_stone_cell) is Workplace, "the quarry still has finite reserves")
	expect(not _zero_chapter.can_evacuate(), "a new timed task cannot immediately evacuate")
	await _capture("zero-preparation")
	if "--preparation-only" in OS.get_cmdline_user_args():
		_finish_zero()
		return
	if "--expire" in OS.get_cmdline_user_args():
		screen.world.match_controller.reset_countdown(1)
		await frames(60)
		expect(screen.world.match_controller.is_finished(), "timeout loses the level")
		screen.retry_game()
		await _navigation()
		expect(Router._current.chapter.phase == ZeroChapter.Phase.PREPARATION, "retry restores the timed checkpoint")
		expect(Router._current.world.match_controller.time_remaining > 700.0, "retry restores the full countdown")
		_finish_zero()
		return
	await _play_preparation()
	_finish_zero()

func _run_lessons() -> void:
	await _dialogue()
	expect(_saw_line("ui.story.tutorial.wake") and _saw_line("ui.story.tutorial.given_name"), "the original eyes and name scenes are played")
	await _practice_controls()
	await _build(&"road", _rules.road_cell)
	if not await _until_phase(ZeroChapter.Phase.WALL): return
	await _dialogue()
	await _build(&"wall", _rules.wall_cell)
	await _until_stage(FirstChapter.Stage.ROYAL_ORDER)
	await _order(_rules.opening_order, &"feast", _rules.order_cell)
	await _until_stage(FirstChapter.Stage.SECOND_ORDER)
	var statue_task: TaskSpec = screen.world.tasks.slots[1]
	await _order(statue_task, &"statue", _rules.followup_cell)
	if not await _until_phase(ZeroChapter.Phase.ROAD): return
	await _dialogue()
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 1, "N exposes the time to enter a tile")
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 2, "N exposes work priorities")
	await key(KEY_N)
	await _paint_plan(&"road", _rules.first_roads)
	if not await _until_phase(ZeroChapter.Phase.ORDERS): return
	await _dialogue()
	await screen._focus_chapter_cell(_rules.delivery_cell)
	await click_at(cell_point(_rules.delivery_cell))
	if screen.nest_popup == null:
		expect(false, "the western barracks can be opened")
		return
	await click(screen.nest_popup.controls[&"orders"])
	var spins: Dictionary = screen.nest_popup._order_rows["stone"].spins
	spins.max.value = _rules.depot_maximum
	spins.min.value = _rules.depot_minimum
	await key(KEY_ESCAPE)
	if not await _until_phase(ZeroChapter.Phase.STATUES): return
	await _dialogue()
	await _paint_plan(&"statue", _rules.statue_cells)
	if not await _until_phase(ZeroChapter.Phase.REMOVE_WALL): return
	await _dialogue()
	var old_source := screen.world.registry.at(_rules.stone_cell) as Workplace
	expect(old_source.entry_cells().all(func(cell: Vector2i): return not screen.world.route_service.walkable(cell)),
		"completed statues close all approaches to the old stone")
	expect(_zero_chapter._transport_delivered > 0, "a carrier completed the central-to-west stone order")
	expect(screen.world.prices.event_count(GameEvents.Kind.BUILDING_BUILT, &"statue") == 4,
		"all three statues completed in addition to the original request")
	expect(not _zero_chapter.allows_placement(null, _rules.statue_cells[0]), "the wall must come down first")
	await _paint_plan(&"demolish", [_rules.wall_cell])
	if not await _until_phase(ZeroChapter.Phase.REMOVE_STATUE): return
	await _dialogue()
	await _paint_plan(&"demolish", [_rules.statue_cells[0]])
	if not await _until_phase(ZeroChapter.Phase.REMOVE_SOURCE): return
	await _dialogue()
	expect(screen.world.route_service.walkable(_rules.statue_cells[0]), "demolition reopened one approach")
	await _paint_plan(&"demolish", [_rules.stone_cell])
	if not await _until_phase(ZeroChapter.Phase.QUARRY): return
	await _dialogue()
	await _paint_plan(&"road", _rules.quarry_roads)
	if await _until_phase(ZeroChapter.Phase.BRIEFING):
		await _dialogue()

func _play_preparation() -> void:
	var route: Array[Vector2i] = [Vector2i(27, 26), Vector2i(28, 26)]
	if "--long-route" in OS.get_cmdline_user_args():
		route.assign([Vector2i(26, 27), Vector2i(26, 28), Vector2i(27, 28), Vector2i(28, 28)])
	else:
		await _paint_plan(&"demolish", [Vector2i(28, 26)])
	await _paint_plan(&"road", route)
	await _build(&"ship", _rules.ship_cell)
	if not await _until_phase(ZeroChapter.Phase.MILITARY, 8400): return
	print("PREPARATION seconds used ", _rules.preparation_seconds - screen.world.match_controller.time_remaining)
	var ship := _zero_chapter.ship()
	expect(ship != null and ship.supplied(), "all cargo was physically delivered")
	if not await _until_phase(ZeroChapter.Phase.EVACUATION): return
	expect(screen.world.registry.at(_rules.breach_cell) == null, "the spider breached the outer wall")
	expect(screen.world.combat.spiders.size() == 1, "one spider appears")
	await screen._focus_chapter_cell(_rules.ship_cell)
	await click_at(cell_point(_rules.ship_cell))
	if not await _until_phase(ZeroChapter.Phase.FAREWELL): return
	await _dialogue()
	await frames(60)
	expect(screen.world.voyage.departed and screen.world.voyage.travelling_characters.has("Military"), "the scout and loaded ship depart")

func _paint_plan(id: StringName, cells: Array[Vector2i]) -> void:
	await key(KEY_B)
	var menu: ConstructionMenu = screen._construction
	if menu == null:
		expect(false, "the build palette opens for " + str(id))
		return
	if id == &"demolish":
		await click(menu.controls[&"demolish"])
	else:
		await choose_building(menu, id)
	for cell in cells:
		await screen._focus_chapter_cell(cell)
		await frames(2)
		await click_at(cell_point(cell))
		if not menu.draft.last_result.allowed():
			print("ZERO DRAFT ", id, " ", cell, " reason ", menu.draft.last_result.code)
	expect(menu.draft.size() == cells.size(), "one plan contains all %d %s actions" % [cells.size(), id])
	if menu.draft.size() != cells.size():
		return
	if id == &"statue":
		var quotes: Dictionary = screen.world.prices.quote_commands(menu.draft.commands())
		var wood: Array[int] = []
		for quote: Array in quotes.values():
			for item: ResourceAmount in quote:
				if item.type.id == &"wood": wood.append(item.amount)
		expect(wood.size() == 3 and wood[0] < wood[1] and wood[1] < wood[2], "statue costs rise inside a single plan")
	for frame in range(900):
		if not menu.controls[&"apply"].disabled:
			break
		await frames(1)
	if menu.controls[&"apply"].disabled:
		print("ZERO APPLY ", id, " budget ", menu.draft.budget_check().code)
		expect(false, "can fund the " + str(id) + " plan")
		return
	await click(menu.controls[&"apply"])
	if is_instance_valid(menu) and menu.draft.size() != 0:
		print("ZERO COMMIT ", id, " reason ", screen.world.build_controller.last_result.code)
		expect(false, "committed the " + str(id) + " plan")

func _until_phase(target: ZeroChapter.Phase, limit := 2200) -> bool:
	for frame in range(limit):
		if _zero_chapter.phase == target:
			return true
		if screen.story.is_modal:
			await _dialogue()
		if screen.world.match_controller.is_finished():
			break
		await frames(1)
	var stock := {}
	for type: ResourceType in screen.world.inventory.registered_types():
		stock[type.id] = screen.world.inventory.available(type)
	print("ZERO STALL expected ", ZeroChapter.Phase.keys()[target], ", actual ",
		ZeroChapter.Phase.keys()[_zero_chapter.phase], ", status ", _zero_chapter.status_text(), ", stock ", stock)
	expect(false, "reached " + ZeroChapter.Phase.keys()[target])
	return false

func _finish_zero() -> void:
	print("ZERO CHAPTER UI ", assertions, " assertions, ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
