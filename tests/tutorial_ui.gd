extends "res://tests/ui_runner.gd"
## Run with isolated user data. Both endings use real input and physical construction.

const ROAD_CELL := Vector2i(26, 26)
const ORDER_CELL := Vector2i(26, 25)

func _run() -> void:
	seed(20261117)
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await _settle_navigation()
	AppSettings.language = "ru"
	if OS.get_cmdline_user_args().has("--tutorial-large-text"):
		AppSettings.text_size = AppSettings.TYPOGRAPHY.minimum_sizes.size() - 1
	AppSettings.apply()
	await _play_variant(&"play", &"build", "feast", false)
	await _return_to_menu()
	AppSettings.language = "en"
	AppSettings.apply()
	await _play_variant(&"tutorial", &"diversion", "statue", true)
	await _return_to_menu()
	await click(Router._current.controls[&"tutorial"])
	await _settle_navigation()
	screen = Router._current
	await click(screen.story.get_node("%SkipDialogue"))
	expect(not screen.story.visible and not get_tree().paused, "skip keeps the existing colony running")
	Router.restart_current()
	await _settle_navigation()
	screen = Router._current
	expect(screen.story.is_modal, "restart shows the introduction again")
	await click(screen.story.get_node("%SkipDialogue"))
	expect(SessionSave.write(screen.world) == OK, "a snapshot without tutorial fields saves")
	await _return_to_menu()
	await click(Router._current.controls[&"continue"])
	await _settle_navigation()
	screen = Router._current
	expect(not screen.story.visible and not get_tree().paused, "an older snapshot resumes as an ordinary match")
	print("TUTORIAL UI: %d assertions, %d failures" % [assertions, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _play_variant(entry: StringName, variant: StringName, ending: String, restore: bool) -> void:
	await click(Router._current.controls[entry])
	await _settle_navigation()
	screen = Router._current
	var story: StoryOverlay = screen.story
	var world: World = screen.world
	expect(story.is_modal and get_tree().paused, "new tutorial pauses for the opening")
	await _capture_tutorial(String(entry) + "-intro")
	expect(world.population.count() == 5 and world.map.surface_at(Vector2i(25, 26)).id == &"road", "authored colony and unfinished road exist immediately")
	expect(world.tasks.slots[0] == story.episode.opening_order, "the feast or statue occupies the first slot")
	var start_time := world.match_controller.time_remaining
	await key(KEY_B)
	await key(KEY_SPACE)
	expect(screen._construction == null and is_equal_approx(world.match_controller.time_remaining, start_time), "modal dialogue blocks construction and freezes time")
	await _dismiss_dialogue()
	expect(story.visible and not story.is_modal and not get_tree().paused, "road hint leaves the world live")
	await _capture_tutorial(String(entry) + "-road")
	await key(KEY_B)
	var menu: ConstructionMenu = screen._construction
	if menu == null:
		expect(false, "B opens construction during the road hint")
		return
	await choose_building(menu, &"road")
	await click_at(cell_point(ROAD_CELL))
	expect(menu.draft.size() == 1 and not story.is_modal, "drawing the road only changes the draft")
	if menu.draft.size() != 1:
		print("Road map point: ", cell_point(ROAD_CELL), " hint: ", story.hint_bounds(), " obstacles: ", screen._construction_obstacles(), " palette: ", menu.panel.get_global_rect())
		return
	await click(menu.controls[&"apply"])
	expect(world.construction_service.at(ROAD_CELL, true) != null and not story.is_modal, "committed road waits for construction")
	await _wait_for_dialogue(story)
	expect(world.map.surface_at(ROAD_CELL).id == &"road", "road is built before dialogue resumes")
	await _dismiss_dialogue()
	expect(story.capture_checkpoint().get("cue") == "order", "order hint follows the road")
	await click(screen.hud.get_node("%TasksTab"))
	var category: Button = screen.hud.task_panel.get_node("%Category")
	if not category.button_pressed:
		await click(category)
	var request: TaskRequest = screen.hud.task_panel.get_node("%Requests").get_child(0)
	var offer: TaskOffer
	for candidate: TaskOffer in request.get_node("%Offers").get_children():
		if candidate.order.variant.id == variant:
			offer = candidate
	if offer == null:
		expect(false, "opening request exposes both options")
		return
	await click(offer.placement)
	menu = screen._construction
	if menu == null:
		expect(false, "selecting the royal order starts placement")
		return
	await click_at(cell_point(ORDER_CELL))
	expect(menu.draft.size() == 1, "the selected order can be drawn")
	if menu.draft.size() != 1:
		print("Order map point: ", cell_point(ORDER_CELL), " hint: ", story.hint_bounds(), " obstacles: ", screen._construction_obstacles())
		return
	expect(not story.hint_bounds().intersects(menu.controls[&"apply"].get_global_rect()), "the hint leaves the apply button unobstructed")
	await _capture_tutorial(String(entry) + "-order")
	await click(menu.controls[&"apply"])
	expect(world.tasks.completed_count == 0 and world.construction_service.at(ORDER_CELL) != null, "applying an order does not award it before assembly")
	if restore:
		await click(screen.hud.controls[&"settings"])
		var pause := Router.top_overlay() as PauseMenu
		if pause == null:
			expect(false, "pause can be opened during a tutorial action")
			return
		await click(pause.controls[&"save"])
		expect(SessionSave.read().get("tutorial", {}).get("cue") == "order", "the pause menu saves the active checkpoint")
		await click(pause.controls[&"main"])
		await _settle_navigation()
		await click(Router._current.controls[&"continue"])
		await _settle_navigation()
		screen = Router._current
		story = screen.story
		world = screen.world
		expect(story.visible and not story.is_modal and world.construction_service.at(ORDER_CELL) != null, "continue resumes the queued order and its hint")
	var time_before_order := world.match_controller.time_remaining
	await _wait_for_dialogue(story)
	var key_text := "ui.story.tutorial." + ending
	var dialogue: Label = story.get_node("%Dialogue")
	expect(tr(key_text) != key_text and dialogue.atr(dialogue.text) == tr(key_text), "the chosen variant gets its own localized closing dialogue")
	await _capture_tutorial(String(entry) + "-ending")
	expect(world.tasks.completed_count == 1 and world.match_controller.time_remaining > time_before_order, "the normal order adds time once")
	await _dismiss_dialogue()
	expect(not story.visible and not get_tree().paused and screen.world == world, "the same colony continues after the ending")
	expect(story.capture_checkpoint().is_empty(), "completed tutorial state is omitted from future saves")

func _settle_navigation() -> void:
	await frames(6)
	for frame in range(120):
		if not Router.is_navigating() and Router.current_screen_key() != &"":
			await frames(6)
			return
		await frames(1)
	expect(false, "screen navigation completes")

func _dismiss_dialogue() -> void:
	var story: StoryOverlay = screen.story
	for line_index in range(12):
		if not story.visible or not story.is_modal:
			return
		await click(story.get_node("%Continue"))
	expect(false, "dialogue reaches a gameplay step or ending")

func _wait_for_dialogue(story: StoryOverlay) -> void:
	for frame in range(2400):
		if story.is_modal:
			return
		await frames(1)
	expect(false, "physical construction leads back to dialogue")

func _return_to_menu() -> void:
	Router.goto(&"main_menu")
	await _settle_navigation()

func _capture_tutorial(label: String) -> void:
	if DisplayServer.get_name() != "headless" and OS.has_environment("COLONY_CAPTURE_DIR"):
		await capture(label, 1)
