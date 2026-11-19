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
	if "--restore-old-quarry" in OS.get_cmdline_user_args():
		await _reload("user://zero-statues.save")
		_zero_chapter = screen.chapter
		expect(_zero_chapter._quarry_cell == ZeroChapter.ORIGINAL_QUARRY_CELL
			and _zero_chapter._quarry_roads == ZeroChapter.ORIGINAL_QUARRY_ROADS,
			"older saves keep the quarry and road lesson from their map")
		expect(screen.world.registry.workplaces().all(func(site: Workplace): return site.output.id != &"wood" or not site.finite_supply),
			"timber in an older zero-island save also becomes inexhaustible")
		_finish_zero()
		return
	var quarry := screen.world.registry.at(_rules.finite_stone_cell) as Workplace
	expect(quarry != null and quarry.finite_supply and not _rules.protected_walls.has_point(quarry.cell),
		"the finite source starts outside the wall")
	if quarry == null:
		_finish_zero()
		return
	expect(quarry.remaining_supply == 1000, "the distant outcrop starts with 1000 stone")
	var inner_stone := screen.world.registry.at(_rules.stone_cell) as Workplace
	if not skip:
		expect(inner_stone != null and not inner_stone.finite_supply and _rules.protected_walls.has_point(inner_stone.cell),
			"the infinite source starts inside the wall")
	var main_entry: Vector2i = screen.world.planner.accessible_entry(screen.world.logistics.main_nest)
	expect(screen.world.route_service.request_route(main_entry, quarry.cell).is_valid(), "the distant quarry is walkable from the start")
	var timber: Array[Workplace] = screen.world.registry.workplaces().filter(func(site: Workplace): return site.output.id == &"wood")
	expect(not timber.is_empty() and timber.all(func(site: Workplace): return not site.finite_supply),
		"all authored timber on the zero island is inexhaustible")
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
	for option: BuildOption in screen.world.build_controller.options:
		if option is NestBuildOption:
			expect(_zero_chapter.allows_tool(option), "the timed task allows " + str(option.id))
	await _capture("zero-preparation")
	if "--housing" in OS.get_cmdline_user_args():
		await _paint_plan(&"base_nest", [Vector2i(21, 28)])
		expect(screen.world.registry.at(Vector2i(21, 28)) is House, "the base nest can be built on the timed map")
		await _paint_plan(&"house", [Vector2i(31, 29)])
		expect(screen.world.construction_service.at(Vector2i(31, 29)) != null, "a barracks can be commissioned on the timed map")
		_finish_zero()
		return
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
	var initial_supply: int = screen.world.registry.at(_rules.finite_stone_cell).remaining_supply
	await _dialogue()
	expect(_saw_line("ui.story.tutorial.wake") and _saw_line("ui.story.tutorial.given_name"), "the original eyes and name scenes are played")
	await _practice_controls()
	expect(not screen.world.inventory.quantities_known, "the original courier lesson still shows infinite resources")
	await _build(&"road", _rules.road_cell)
	if not await _until_phase(ZeroChapter.Phase.WALL): return
	await _dialogue()
	await _build(&"wall", _rules.wall_cell)
	await _until_stage(FirstChapter.Stage.ROYAL_ORDER)
	await _order(_rules.opening_order, &"feast", _rules.order_cell)
	await _until_stage(FirstChapter.Stage.SECOND_ORDER)
	var statue_task: TaskSpec
	for task: TaskSpec in screen.world.tasks.slots:
		if task != null and task.variants.any(func(variant: TaskVariant): return _chapter.allows_order(task.id, variant.id)):
			statue_task = task
			break
	expect(statue_task != null, "the original follow-up order is offered")
	if statue_task == null: return
	await _order(statue_task, &"statue", _rules.followup_cell)
	await _until_stage(FirstChapter.Stage.WORKER_ADVICE)
	await _talk_to(&"Worker")
	await _dialogue()
	expect(_saw_line("ui.chapter.worker_info"), "the original explanation of building improvements is played")
	expect(_zero_chapter.guide_cells() == [_rules.timber_cell, _rules.stone_cell], "both upgrades have gold markers")
	await key(KEY_B)
	var menu: ConstructionMenu = screen._construction
	if menu == null:
		expect(false, "the upgrade palette opens")
		return
	expect(not menu.controls[&"demolish"].visible, "the palette hides demolition when there is nothing eligible to remove")
	await choose_building(menu, &"quarry")
	await screen._focus_chapter_cell(_rules.stone_cell)
	await frames(2)
	await click_at(cell_point(_rules.stone_cell))
	await choose_building(menu, &"sawmill")
	await screen._focus_chapter_cell(_rules.timber_cell)
	await frames(2)
	await click_at(cell_point(_rules.timber_cell))
	expect(menu.draft.size() == 2 and not menu.controls[&"apply"].disabled, "sawmill and northern quarry share a funded plan")
	await click(menu.controls[&"apply"])
	if not await _until_phase(ZeroChapter.Phase.STATUES): return
	await _dialogue()
	expect(not screen.world.inventory.quantities_known, "the three-statue commission still shows infinite resources")
	var old_source := screen.world.registry.at(_rules.stone_cell) as Workplace
	expect(old_source.improvement == _rules.wishes[2], "the northern stone can be upgraded before its demolition lesson")
	var north := old_source.cell + Vector2i.UP
	expect(screen.world.registry.at(north) is DefenseBuilding and not screen.world.route_service.walkable(north),
		"the wall closes the north side of the old stone")
	expect(old_source.entry_cells().all(func(cell: Vector2i): return screen.world.route_service.request_route(
		screen.world.planner.accessible_entry(screen.world.logistics.main_nest), cell).is_valid()),
		"all approaches to the old stone are reachable before the commission")
	var statue_card := await _choose_statue_order()
	if statue_card == null:
		expect(false, "the three-statue commission appears in Tasks")
		return
	await _paint_plan(&"statue", _rules.statue_cells, statue_card)
	expect(screen.save_game("user://zero-statues.save") == OK, "the batch can be saved while its materials are in transit")
	await _reload("user://zero-statues.save")
	_zero_chapter = screen.chapter
	old_source = screen.world.registry.at(_rules.stone_cell) as Workplace
	if not await _until_phase(ZeroChapter.Phase.REMOVE_WALL): return
	await _dialogue()
	expect(_saw_line("ui.chapter.infinite_question") and _saw_line("ui.zero.real_stock") and screen.world.inventory.quantities_known,
		"the planner explains the queen's infinity sign and reveals the real stock")
	expect(old_source.entry_cells().all(func(cell: Vector2i): return not screen.world.route_service.walkable(cell)),
		"completed statues close all approaches to the old stone")
	expect(screen.world.prices.event_count(GameEvents.Kind.BUILDING_BUILT, &"statue") == 4,
		"all three statues completed in addition to the original request")
	expect(not _zero_chapter.allows_placement(null, _rules.statue_cells[0]), "the wall must come down first")
	await _paint_plan(&"demolish", _rules.demolition_wall_cells)
	if not await _until_phase(ZeroChapter.Phase.REMOVE_STATUE): return
	await _dialogue()
	await _paint_plan(&"demolish", [_rules.statue_cells[0]])
	if not await _until_phase(ZeroChapter.Phase.REMOVE_SOURCE): return
	await _dialogue()
	expect(screen.world.route_service.walkable(_rules.statue_cells[0]), "demolition reopened one approach")
	expect(screen.world.registry.at(_rules.statue_cells[1]) != null and screen.world.registry.at(_rules.statue_cells[2]) != null,
		"the statue lesson leaves the other two statues standing")
	await _paint_plan(&"demolish", [_rules.stone_cell])
	if not await _until_phase(ZeroChapter.Phase.QUARRY): return
	await _dialogue()
	expect(screen.world.registry.at(_rules.stone_cell) == null, "one demolition plan removes the improved northern source")
	var quarry := screen.world.registry.at(_rules.finite_stone_cell) as Workplace
	expect(quarry.remaining_supply == initial_supply,
		"workers prefer nearby jobs and leave the distant stone untouched before the road")
	expect(_zero_chapter.status_text() == tr("ui.zero.quarry_goal") % [0, _rules.quarry_target], "the quarry objective starts with its production counter")
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 1, "N exposes the time to enter a tile")
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 2, "N exposes work priorities")
	await key(KEY_N)
	var roads := _rules.quarry_roads.duplicate()
	roads.erase(_rules.finite_stone_cell)
	await _paint_plan(&"road", roads)
	expect(_zero_chapter.phase == ZeroChapter.Phase.QUARRY, "roads alone do not finish the quarry objective")
	if not await _until_phase(ZeroChapter.Phase.ORDERS, 12000): return
	await _dialogue()
	var totals: RichTextLabel = screen.hud.colony_summary.get_node("%Totals")
	expect(not totals.get_parsed_text().contains("∞"), "real stocks remain visible during the courier lesson after meeting the planner")
	expect(screen.save_game("user://zero-orders.save") == OK, "the courier order lesson saves")
	await _reload("user://zero-orders.save")
	_zero_chapter = screen.chapter
	quarry = screen.world.registry.at(_rules.finite_stone_cell) as Workplace
	totals = screen.hud.colony_summary.get_node("%Totals")
	expect(_zero_chapter.phase == ZeroChapter.Phase.ORDERS and screen.world.inventory.quantities_known and not totals.get_parsed_text().contains("∞"), "loading the courier order lesson preserves the stock reveal")
	expect(quarry.remaining_supply <= initial_supply - _rules.quarry_target and not _zero_chapter._is_road(_rules.finite_stone_cell),
		"mining enough stone finishes the lesson before the marked route is fully paved")
	expect(_saw_line("ui.chapter.carry_command") and _saw_line("ui.chapter.coffee") and _saw_line("ui.chapter.berry"),
		"the original quarrel plays before the delivery lesson")
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
	if await _until_phase(ZeroChapter.Phase.BRIEFING):
		expect(_zero_chapter._transport_delivered > 0, "a carrier delivered the west barracks stone order")
		await _dialogue()

func _choose_statue_order() -> ConstructionCard:
	await click(screen.hud.get_node("%TasksTab"))
	var category: Button = screen.hud.task_panel.get_node("%Category")
	if not category.button_pressed:
		await click(category)
	for request: TaskRequest in screen.hud.task_panel.get_node("%Requests").get_children():
		if request.task != _rules.statue_order:
			continue
		var offer: TaskOffer = request.get_node("%Offers").get_child(0)
		await click(offer.placement)
		return offer.placement
	return null

func _play_preparation() -> void:
	var route: Array[Vector2i] = [Vector2i(31, 26), Vector2i(35, 28)]
	if "--long-route" in OS.get_cmdline_user_args():
		route.assign([Vector2i(26, 27), Vector2i(26, 28), Vector2i(27, 28), Vector2i(28, 28), Vector2i(35, 28)])
	else:
		await _paint_plan(&"demolish", [Vector2i(31, 26)])
	await screen._focus_chapter_cell(_rules.quarry_depot_cell)
	await click_at(cell_point(_rules.quarry_depot_cell))
	if screen.nest_popup == null:
		expect(false, "the east barracks can be opened")
		return
	await click(screen.nest_popup.controls[&"orders"])
	screen.nest_popup._order_rows["stone"].spins.min.value = 0
	await key(KEY_ESCAPE)
	await _paint_plan(&"road", route)
	await _paint_plan(&"ship", [_rules.ship_cell])
	var time_before: float = screen.world.match_controller.time_remaining
	expect(screen.save_game("user://zero-preparation.save") == OK, "the active timed task can be saved")
	await _reload("user://zero-preparation.save")
	_zero_chapter = screen.chapter
	expect(screen.world.match_controller.time_remaining <= time_before and screen.world.match_controller.time_remaining > time_before - 15.0, "loading restores the remaining time")
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

func _paint_plan(id: StringName, cells: Array[Vector2i], order_card: ConstructionCard = null) -> void:
	if order_card == null:
		await key(KEY_B)
	var menu: ConstructionMenu = screen._construction
	if menu == null:
		expect(false, "the build palette opens for " + str(id))
		return
	if id == &"demolish":
		expect(menu.controls[&"demolish"].visible and not menu.controls[&"demolish"].disabled, "the active demolition tool is usable")
		await click(menu.controls[&"demolish"])
	elif order_card == null:
		await choose_building(menu, id)
	for cell in cells:
		await screen._focus_chapter_cell(cell)
		await frames(2)
		var price_before := order_card._cost.get_parsed_text() if order_card != null else ""
		await click_at(cell_point(cell))
		if order_card != null and cell == cells[0]:
			expect(order_card._cost.get_parsed_text() != price_before, "drafting updates the order card immediately")
			await click_at(cell_point(cell), MOUSE_BUTTON_RIGHT)
			expect(order_card._cost.get_parsed_text() == price_before, "erasing a draft restores the previous price")
			await click_at(cell_point(cell))
		if not menu.draft.last_result.allowed():
			print("ZERO DRAFT ", id, " ", cell, " reason ", menu.draft.last_result.code)
	if id == &"demolish" and _zero_chapter.phase == ZeroChapter.Phase.REMOVE_STATUE:
		await screen._focus_chapter_cell(_rules.statue_cells[1])
		await frames(2)
		await click_at(cell_point(_rules.statue_cells[1]))
		expect(menu.draft.size() == 1, "the statue lesson accepts only one demolition per plan")
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
		await _capture("zero-uncommitted")
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
	print("ZERO STALL expected ", ZeroChapter.Phase.find_key(target), ", actual ",
		ZeroChapter.Phase.find_key(_zero_chapter.phase), ", status ", _zero_chapter.status_text(), ", stock ", stock)
	for site: ConstructionSite in screen.world.construction_service.sites:
		print("ZERO SITE ", site.option.id, " ", site.cell, " delivered ", site.delivered, " transit ", site.transit,
			" progress ", site.progress, " crates ", site.crates.keys())
	for ant: AntAgent in screen.world.population.agents():
		if ant.role == AntAgent.Role.CARRIER:
			print("ZERO CARRIER ", ant.global_position, " ", AntAgent.Status.keys()[ant.status], " satiety ", ant.needs.satiety)
	expect(false, "reached " + str(ZeroChapter.Phase.find_key(target)))
	return false

func _finish_zero() -> void:
	print("ZERO CHAPTER UI ", assertions, " assertions, ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
