extends "res://tests/ui_runner.gd"

func _run() -> void:
	seed(20261025)
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	open_fixed_match()
	await frames(45)
	screen = Router._current
	for size in range(AppSettings.TYPOGRAPHY.minimum_sizes.size()):
		AppSettings.text_size = size
		AppSettings.changed.emit()
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
	AppSettings.changed.emit()
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
	await choose_building(menu, &"road")
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
	await click(menu.controls[&"apply"])
	expect(screen._construction == null, "road plan commits")

	world.build_controller.construction = construction
	await click(screen.hud.get_node("%TasksTab"))
	var panel: TaskPanel = screen.hud.task_panel
	var task: TaskSpec = world.tasks.slots[0]
	var card: Button = panel.get_node("%Requests").get_child(0).get_node("Actions/Diversion")
	expect(card.icon != null, "task variant shows an icon")
	await click(card)
	menu = screen._construction
	if menu != null: await click(menu.controls[&"cancel"])
	expect(world.tasks.active_order_id == &"", "cancel releases the unfinished order")
	card = panel.get_node("%Requests").get_child(0).get_node("Actions/Diversion")
	await click(card)
	menu = screen._construction
	if menu == null or menu.order_option != task.diversion:
		expect(false, "task card opens the selected order")
		get_tree().quit(1)
		return
	expect(panel.visible and menu.panel.position.x > panel.position.x, "order details open on the right of the task list")
	expect(not world.build_controller.options.has(task.diversion), "order stays outside the construction catalog")
	await click_at(cell_point(Vector2i(25, 27)))
	await click_at(cell_point(Vector2i(26, 27)))
	expect(menu.draft.size() == 1, "order limits the draft to one building")
	await click(menu.controls[&"apply"])
	var site := world.build_controller.construction.at(Vector2i(25, 27))
	expect(site != null and world.tasks.completed_count == 0, "placing the order queues construction without granting a reward")
	expect(world.tasks.active_order_id == task.id, "the order stays active while being built")
	var snapshot := SessionSave.capture(world)
	snapshot.options.append(str(task.diversion.id))
	var restored := LevelLayout.create_world(snapshot.layout)
	restored.auto_start = false
	add_child(restored)
	SessionSave.apply(restored, snapshot)
	expect(restored.tasks.active_order_id == task.id and restored.build_controller.construction.at(Vector2i(25, 27)) != null, "a save restores the active order and its site")
	expect(not restored.build_controller.options.has(task.diversion), "legacy saves do not add orders to the regular catalog")
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
	var old_time := world.match_controller.time_remaining
	if site != null: world.build_controller.finish_construction(site)
	expect(world.tasks.completed_count == 1, "finished order completes the selected task")
	expect(absf(world.match_controller.time_remaining - old_time - task.time_reward_for(true)) < 0.5, "selected variant grants its own time reward")
	var limited: SceneBuildOption = task.diversion.duplicate()
	limited.instance_limit = 2
	world.build_controller.options.append(limited)
	var first := BuildCommand.create(Vector2i(26, 27), limited)
	var second := BuildCommand.create(Vector2i(27, 27), limited)
	expect(not world.build_controller.try_build_plan([first, second]) and world.build_controller.last_result.code == PlacementCheck.Code.INSTANCE_LIMIT, "batch limit includes a previously built instance")
	expect(world.build_controller.try_build_plan([first]), "one additional instance fits within the configured limit")
	expect(world.build_controller.placement_check(limited, second.cell).code == PlacementCheck.Code.INSTANCE_LIMIT, "an active construction site counts once toward the limit")
	print("ORDER CONSTRUCTION UI: %d checks, %d failures" % [assertions, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
