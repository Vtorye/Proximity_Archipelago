extends "res://tests/ui_runner.gd"

func _run() -> void:
	seed(20261025)
	get_viewport().add_child(load("res://game/application/boot.tscn").instantiate())
	await frames(35)
	open_fixed_match()
	await frames(45)
	screen = Router._current
	for size in range(AppSettings.TYPOGRAPHY.minimum_sizes.size()):
		AppSettings.text_size = size
		AppSettings.apply()
		await click(screen.hud.controls[&"settings"])
		var pause := Router.top_overlay() as PauseMenu
		if pause == null:
			expect(false, "settings opens the pause menu")
			get_tree().quit(1)
			return
		var header: WindowHeader = pause.get_node("%WindowHeader")
		expect(header.handle.text == "ui.pause.title" and pause.get_node("%Content").find_children("*", "Label").is_empty(), "pause appears once as the window title")
		expect(pause.controls[&"resume"].get_theme_font_size("font_size") == AppSettings.minimum_text_size(), "pause buttons use the selected compact font size")
		await click(pause.controls[&"resume"])
	AppSettings.text_size = AppSettings.TYPOGRAPHY.default_index
	AppSettings.apply()
	var world: World = screen.world
	var construction := world.build_controller.construction
	world.build_controller.construction = null
	for type in world.inventory.registered_types(): world.inventory.add(type, 200)
	screen.camera.position = Vector2(400, 464)
	screen.camera.force_update_scroll()
	await click(screen.hud.controls[&"build"])
	var menu: ConstructionMenu = screen._construction
	if menu == null or menu.draft.controller == null:
		expect(false, "construction initializes from the HUD button")
		get_tree().quit(1)
		return
	for action in [&"demolish", &"apply", &"cancel"]:
		var button: Button = menu.controls[action]
		expect(button.is_visible_in_tree() and menu.panel.is_ancestor_of(button), "plan action is inside the construction panel")
	expect(menu.controls[&"apply"].disabled and menu.controls[&"undo"].disabled, "empty plan disables apply and undo")
	await click(menu.controls[&"demolish"])
	expect(menu.controls[&"demolish"].button_pressed, "demolition starts from the palette")
	await choose_building(menu, &"road")
	var build_strip_bottom := menu.buildings_panel.get_global_rect().end.y
	var start := Vector2i(23, 27)
	var end := Vector2i(29, 27)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = cell_point(start)
	get_viewport().push_input(press, true)
	var move := InputEventMouseMotion.new()
	move.position = cell_point(end)
	move.relative = move.position - press.position
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move, true)
	press.pressed = false
	press.button_mask = 0
	press.position = move.position
	get_viewport().push_input(press, true)
	expect(menu.draft.size() == 7, "drag paints all seven road cells")
	await click(screen.hud.controls[&"build"])
	expect(not menu.panel.visible and menu.draft.size() == 7, "closing the palette keeps the draft")
	for key in [&"apply", &"cancel", &"demolish"]:
		expect(not menu.controls[key].is_visible_in_tree(), "plan action closes with the palette")
	expect(menu.controls[&"undo"].is_visible_in_tree(), "stroke undo stays on the HUD")
	var undo_button: Button = menu.controls[&"undo"]
	var pan_button: Button = menu.controls[&"move"]
	expect(pan_button.get_parent() == undo_button.get_parent() and pan_button.get_index() == undo_button.get_index() + 1 and pan_button.icon != null and undo_button.icon != null, "icon-only pan and undo sit together on the HUD")
	await click(undo_button)
	expect(menu.draft.size() == 0, "the HUD undo icon removes the stroke")
	await click_at(cell_point(start))
	var undo := InputEventKey.new()
	undo.physical_keycode = KEY_Z
	undo.ctrl_pressed = true
	undo.pressed = true
	get_viewport().push_input(undo, true)
	expect(menu.draft.size() == 0, "Ctrl+Z undoes the stroke with the palette closed")
	await click_at(cell_point(start))
	expect(menu.draft.size() == 1, "map editing remains active with the palette closed")
	await click(screen.hud.controls[&"build"])
	await click(menu.controls[&"apply"])
	expect(screen._construction == null, "road plan commits")

	world.build_controller.construction = construction
	await click(screen.hud.get_node("%TasksTab"))
	var panel: TaskPanel = screen.hud.task_panel
	var categories: PanelContainer = panel.get_node("%Categories")
	var task_strip: PanelContainer = panel.get_node("%TaskStrip")
	var task_scroll: ScrollContainer = panel.get_node("%Scroll")
	expect(categories.get_node("WindowContents/Content").find_children("*", "Button", true, false).size() == 1 and not task_strip.visible, "tasks open with a single construction category and a separate window toggle")
	await click(panel.get_node("%Category"))
	var strip_rect := task_strip.get_global_rect()
	var categories_rect := categories.get_global_rect()
	expect(task_strip.visible and is_equal_approx(strip_rect.end.y, build_strip_bottom) and is_equal_approx(categories_rect.end.y, strip_rect.end.y), "the task strip uses the ordinary construction strip's bottom alignment")
	expect(strip_rect.position.x > categories_rect.end.x and task_scroll.size.y <= get_viewport().get_visible_rect().size.y / 5.0, "the task content stays beside its category and within one fifth of the screen below the title bar")
	var task: TaskSpec = world.tasks.slots[0]
	var choice: TaskVariant = task.variant_by_id(&"diversion")
	for index in range(world.tasks.slots.size()):
		var request := _request(panel, index)
		var title: Label = request.get_node("%Title")
		var first_card := _offer_card(panel, index, 0)
		expect(title.text == "Ур.1 (%d)" % (index + 1) and title.tooltip_text.is_empty(), "each task has a short numbered title without a tooltip")
		expect(first_card.is_visible_in_tree() and title.get_global_rect().end.y <= first_card.global_position.y, "task cards sit below the numbered title")
		if index > 0:
			expect(request.global_position.x >= _request(panel, index - 1).get_global_rect().end.x, "task groups share one horizontal strip")
	AppSettings.text_size = AppSettings.TYPOGRAPHY.minimum_sizes.size() - 1
	AppSettings.apply()
	await frames(7)
	var large_card := _offer_card(panel, 0, 1)
	expect(get_viewport().get_visible_rect().encloses(task_strip.get_global_rect()) and task_scroll.size.y <= get_viewport().get_visible_rect().size.y / 5.0, "task content keeps its height limit at maximum text size")
	expect(large_card.get_global_rect().encloses(large_card._cost.get_global_rect()), "the price fits inside the card at maximum text size")
	expect(large_card._cost.get_theme_font_size(&"normal_font_size") == AppSettings.minimum_text_size(), "compact task prices respect the larger text setting")
	AppSettings.text_size = AppSettings.TYPOGRAPHY.default_index
	AppSettings.apply()
	await frames(6)
	var extra := TaskVariant.new()
	extra.id = &"extra"
	extra.building = choice.building
	task.variants.append(extra)
	panel._queue_refresh()
	await frames(4)
	var extra_card := _offer_card(panel, 0, 2)
	expect(extra_card.option == extra.building and is_equal_approx(extra_card.global_position.y, _offer_card(panel, 0, 0).global_position.y), "an order can show more than two cards in one row")
	task.variants.erase(extra)
	panel._queue_refresh()
	await frames(4)
	var card := _offer_card(panel, 0, 1)
	var offer := _offer(panel, 0, 1)
	expect(card.scene_file_path == "res://game/ui/construction_card.tscn" and card._image.texture != null and card._image.get_global_rect().end.y <= card._cost.global_position.y, "task uses the palette construction card with its image above its price")
	var card_rect := card.get_global_rect()
	var reward_rect := offer.reward.get_global_rect()
	expect(card_rect.end.y <= reward_rect.position.y and not card.is_ancestor_of(offer.reward) and absf(card_rect.get_center().x - reward_rect.get_center().x) <= 1.0, "the reward sits centered below its construction card")
	var horizontal_bar := task_scroll.get_h_scroll_bar()
	var scroll_bottom := horizontal_bar.global_position.y if horizontal_bar.visible else task_scroll.get_global_rect().end.y
	expect(not task_scroll.get_v_scroll_bar().visible and reward_rect.end.y <= scroll_bottom, "rewards remain fully visible at default text size")
	expect(card_rect.encloses(card._info.get_global_rect()) and card._info.global_position.x > card._image.global_position.x and card._info.global_position.y < card._cost.global_position.y, "info sits inside the upper-right corner of the card")
	expect(is_equal_approx(_offer_card(panel, 0, 0).get_global_rect().position.y, card.get_global_rect().position.y), "variants are arranged horizontally")
	await click(card._info)
	expect(screen.hud._task_details.visible and screen._construction == null, "the card info opens shared details without selecting the variant")
	for text_size in [0, AppSettings.TYPOGRAPHY.minimum_sizes.size() - 1]:
		AppSettings.text_size = text_size
		AppSettings.apply()
		await frames(5)
		var details: BuildDetailsPanel = screen.hud._task_details
		var description: Label = details.get_node("%Description")
		var body_size := description.get_theme_font_size(&"font_size")
		var ordinary_size := maxi(AppSettings.minimum_text_size(), AppSettings.TYPOGRAPHY.body_size)
		expect(body_size < ordinary_size, "i descriptions use smaller text than the main interface")
		expect(details.get_node("%Parameters").get_theme_font_size(&"font_size") == body_size and details.get_node("%Price").get_theme_font_size(&"normal_font_size") == body_size, "description, parameters and prices share compact typography")
		if DisplayServer.get_name() != "headless":
			await capture("details-text-%d" % text_size, 1)
	AppSettings.text_size = AppSettings.TYPOGRAPHY.default_index
	AppSettings.apply()
	await frames(5)
	card = _offer_card(panel, 0, 1)
	await click(card)
	menu = screen._construction
	if menu != null: await click(menu.controls[&"cancel"])
	expect(world.tasks.placed_order(task) == null, "cancel leaves the unplaced task open")
	card = _offer_card(panel, 0, 1)
	await click(card)
	menu = screen._construction
	if menu == null or menu.order == null or menu.order.variant != choice:
		expect(false, "task card opens the selected order")
		get_tree().quit(1)
		return
	expect(panel.visible and not menu.panel.get_global_rect().intersects(task_strip.get_global_rect()), "plan controls leave the task strip unobstructed")
	expect(not menu.buildings_panel.visible, "task placement only opens plan controls beside the task blocks")
	var selected_style := card.get_theme_stylebox(&"pressed") as StyleBoxFlat
	expect(card.button_pressed and selected_style != null and selected_style.border_width_top >= 3 and not _offer_card(panel, 0, 0).button_pressed, "active variant has a thick frame")
	await click(_offer_card(panel, 0, 0)._info)
	expect(card.button_pressed and menu.order.variant == choice, "using info leaves the active variant selected")
	await click(_offer_card(panel, 0, 0)._info)
	await click(menu.controls[&"move"])
	expect(not task_strip.visible and categories.visible, "pan mode collapses only the strip")
	await click(menu.controls[&"move"])
	expect(task_strip.visible, "leaving pan mode restores the selected task category")
	expect(not world.build_controller.options.has(choice.building), "order stays outside the construction catalog")
	await click_at(cell_point(Vector2i(25, 27)))
	await click_at(cell_point(Vector2i(26, 27)))
	expect(menu.draft.size() == 1, "order limits the draft to one building")
	expect(not _offer_card(panel, 0, 0).disabled and world.tasks.placed_order(task) == null, "an unsubmitted map draft leaves alternatives available")
	var other: TaskSpec = world.tasks.slots[1]
	var other_index := other.variants.find_custom(func(candidate: TaskVariant) -> bool: return candidate.building == choice.building)
	expect(other_index >= 0, "two tasks offer the same building in this fixture")
	if other_index < 0:
		get_tree().quit(1)
		return
	task_scroll.ensure_control_visible(_offer_card(panel, 1, other_index))
	await frames(2)
	await click(_offer_card(panel, 1, other_index))
	expect(_offer_card(panel, 1, other_index).button_pressed and not card.button_pressed, "the frame follows the current variant")
	expect(screen._construction == menu and menu.order.task == other and menu.draft.size() == 1, "selecting the second task keeps the first placement in the same map preview")
	await click_at(cell_point(Vector2i(25, 27)))
	expect(menu.draft.task_orders().size() == 1 and menu.draft.task_orders()[0].task == task, "another task cannot overwrite an occupied draft cell")
	var other_cell := Vector2i(26, 27)
	await click_at(cell_point(other_cell))
	expect(menu.draft.size() == 2 and menu.draft.task_orders().size() == 2, "one draft contains both tasks")
	if menu.draft.size() != 2:
		get_tree().quit(1)
		return
	var expected_time: float = menu.draft.task_orders()[0].time_reward() + menu.draft.task_orders()[1].time_reward()
	var displayed_reward := menu._reward.get_parsed_text().replace(" ", " ").split(" ", false)
	expect(displayed_reward.has(str(int(expected_time))) and displayed_reward.has("2"), "the plan shows both time and resource rewards summed")
	var displayed_cost := menu._cost.get_parsed_text().replace(" ", " ").split(" ", false)
	for entry in choice.building.costs:
		expect(displayed_cost.has(str(entry.amount * 2)), "the plan price displays each resource summed")
	expect(not _offer_card(panel, 0, 0).disabled and not _offer_card(panel, 1, 0).disabled, "both tasks remain selectable until the plan is submitted")
	await click(menu.controls[&"undo"])
	expect(menu.draft.size() == 1 and menu.draft.task_orders()[0].task == task, "undo removes only the most recent placement")
	expect(not menu._reward.get_parsed_text().replace(" ", " ").split(" ", false).has(str(int(expected_time))), "undo recalculates the estimated reward")
	await click_at(cell_point(other_cell))
	await click(menu.controls[&"apply"])
	var site := construction.at(Vector2i(25, 27))
	var other_site := construction.at(other_cell)
	expect(site != null and other_site != null and other_site.option == site.option and other_site.order.task == other, "one confirmation commits two orders for the same building")
	expect(world.tasks.completed_count == 0 and _offer_card(panel, 0, 0).disabled and _offer_card(panel, 1, 0).disabled and not _offer_card(panel, 2, 0).disabled, "only submitted tasks lock and no reward is paid before completion")
	var submitted := _offer_card(panel, 0, 1)
	expect(submitted.disabled and submitted.button_pressed and submitted.get_theme_stylebox(&"disabled") == submitted.get_theme_stylebox(&"pressed"), "a submitted variant keeps its frame after the order is locked")
	expect(world.tasks.placed_order(task) == site.order, "placing a second task cannot replace the first order")
	var snapshot := SessionSave.capture(world)
	snapshot.options.append(str(choice.building.id))
	var restored := LevelLayout.create_world(snapshot.layout)
	restored.auto_start = false
	add_child(restored)
	SessionSave.apply(restored, snapshot)
	var restored_site := restored.build_controller.construction.at(Vector2i(25, 27))
	expect(restored_site != null and restored_site.order != null and restored_site.order.task.id == task.id and restored_site.order.variant.id == choice.id, "a save restores the active order and its variant")
	var restored_other := restored.build_controller.construction.at(other_cell)
	expect(restored_other != null and restored_other.order != null and restored_other.order.task.id == other.id, "a save restores both orders separately")
	if restored_other != null:
		restored.build_controller._remove_site(restored_other)
		expect(restored.tasks.start_order(other.id, other.variants[0].id) != null and restored.tasks.start_order(task.id, choice.id) == null, "cancelling a site reopens only its task")
	expect(not restored.build_controller.options.has(choice.building), "legacy saves do not add orders to the regular catalog")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.tasks["active_order_id"] = str(task.id)
	legacy.tasks["active_order_diversion"] = true
	for state: Dictionary in legacy.sites:
		state.erase("task_id")
		state.erase("variant_id")
	var legacy_world := LevelLayout.create_world(legacy.layout)
	legacy_world.auto_start = false
	add_child(legacy_world)
	SessionSave.apply(legacy_world, legacy)
	var legacy_site := legacy_world.build_controller.construction.at(Vector2i(25, 27))
	expect(legacy_site != null and legacy_site.order != null and legacy_site.order.variant.id == &"diversion", "legacy single-order saves restore the chosen variant")
	legacy_world.free()
	# A version 1 snapshot from before the order system used these IDs.
	snapshot.tasks.level = 1
	snapshot.tasks.closed = 1
	snapshot.tasks.completed_count = 1
	snapshot.tasks.slots = ["stage_1_task_0", "stage_1_task_1", "stage_1_task_2"]
	snapshot.tasks.pool = ["stage_1_task_4"]
	snapshot.tasks.erase("active_order_id")
	snapshot.tasks.erase("active_order_diversion")
	restored.tasks.restore_state(snapshot.tasks)
	expect(restored.tasks.capture_state().pool == ["house_feast"], "legacy stage_1_task_4 in the pool is migrated")
	expect(restored.tasks.capture_state().slots == ["statue_feast", "quarry_feast", "farm_feast"], "legacy slots retain their order")
	expect(restored.tasks.closed == 1 and restored.tasks.completed_count == 1, "legacy task progress is preserved")
	snapshot.tasks.slots[1] = "removed_task"
	snapshot.tasks.pool[0] = "removed_pool_task"
	restored.tasks.restore_state(snapshot.tasks)
	var remaining: Dictionary = restored.tasks.capture_state()
	expect(not remaining.slots.has("") and remaining.pool.size() == 1 and restored.tasks.closed == 1, "unmapped tasks are replaced without losing progress or blocking the stage")
	restored.free()
	if other_site != null: world.build_controller.finish_construction(other_site)
	expect(world.tasks.completed_count == 1 and world.tasks.slots.has(task) and not world.tasks.slots.has(other), "finishing the second site credits only the second task")
	var old_time := world.match_controller.time_remaining
	if site != null: world.build_controller.finish_construction(site)
	expect(world.tasks.completed_count == 2, "each finished site completes its own task once")
	expect(absf(world.match_controller.time_remaining - old_time - (choice.reward_seconds if choice.reward_seconds >= 0.0 else task.reward_seconds)) < 0.5, "selected variant grants its own time reward")
	var limited: SceneBuildOption = choice.building.duplicate()
	limited.instance_limit = 3
	world.build_controller.unlock_option(limited)
	var first := BuildCommand.create(Vector2i(28, 27), limited)
	var second := BuildCommand.create(Vector2i(27, 27), limited)
	expect(not world.build_controller.try_build_plan([first, second]) and world.build_controller.last_result.code == PlacementCheck.Code.INSTANCE_LIMIT, "batch limit includes a previously built instance")
	expect(world.build_controller.try_build_plan([first]), "one additional instance fits within the configured limit")
	expect(world.build_controller.placement_check(limited, second.cell).code == PlacementCheck.Code.INSTANCE_LIMIT, "an active construction site counts once toward the limit")
	await _check_new_nest_popup(world)
	print("ORDER CONSTRUCTION UI: %d checks, %d failures" % [assertions, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_new_nest_popup(world: World) -> void:
	var controller := world.build_controller
	var house_option: SceneBuildOption = preload("res://game/building/options/barracks.tres")
	var cell := Vector2i(29, 26)
	var placed := controller.try_build(house_option, cell)
	var site := controller.construction.at(cell)
	if site != null:
		placed = controller.finish_construction(site)
	var house := world.registry.at(cell) as House
	expect(placed and house != null and not house.is_main_nest, "build a new nest through the construction controller")
	if house == null:
		return
	await click_at(cell_point(cell), MOUSE_BUTTON_RIGHT)
	var popup: NestMenu = screen.nest_popup
	var initialized := popup != null and popup.house == house and popup.controls.has(&"residents")
	expect(initialized, "right click opens and initializes the new nest popup")
	if not initialized:
		return
	expect(popup.get_node("%InventoryTab").visible, "new nest opens on its inventory")
	await click(popup.controls[&"orders"])
	expect(popup.get_node("%OrdersTab").visible and popup.get_node("%OrderRows").get_child_count() > 0, "new nest shows its stock orders")
	await click(popup.controls[&"residents"])
	expect(popup.get_node("%ResidentsTab").visible, "new nest shows its residents")
	await click(popup.controls[&"close"])
	expect(screen.nest_popup == null, "new nest popup can be closed")

func _offer_card(panel: TaskPanel, task_index: int, choice_index: int) -> ConstructionCard:
	return _offer(panel, task_index, choice_index).placement

func _request(panel: TaskPanel, index: int) -> TaskRequest:
	return panel.get_node("%Requests").get_child(index) as TaskRequest

func _offer(panel: TaskPanel, task_index: int, choice_index: int) -> TaskOffer:
	return _request(panel, task_index).get_node("%Offers").get_child(choice_index) as TaskOffer
