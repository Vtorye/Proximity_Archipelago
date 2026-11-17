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
	expect(screen.hud.get_node("%Timer").visible and not screen.world.match_controller.countdown_suspended, "skipping immediately restores the normal countdown")
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
	var dialogue: Label = story.get_node("%Dialogue")
	var portrait: TextureRect = story.get_node("%Portrait")
	var starting_characters := dialogue.visible_characters
	var voice: AudioStreamPlayer = story.get_node("%Voice")
	var voice_played := voice.playing
	var portrait_moved := portrait.position.y < 0.0
	for frame in range(9):
		await frames(1)
		voice_played = voice_played or voice.playing
		portrait_moved = portrait_moved or portrait.position.y < 0.0
	expect(starting_characters >= 0 and dialogue.visible_characters > starting_characters, "the dialogue appears character by character")
	expect(voice.stream != null and voice_played, "the voice player starts while characters appear")
	expect(portrait_moved and is_zero_approx(portrait.position.y), "the new portrait rises and returns to its resting offset")
	expect(portrait.get_global_rect().position.y < story.get_node("%DialoguePanel").get_global_rect().position.y, "the portrait rises outside the dialogue box")
	if dialogue.visible_characters != -1:
		await click(story.get_node("%Continue"))
	expect(dialogue.visible_characters == -1 and story.is_modal, "the first press reveals the line without advancing")
	await _capture_tutorial(String(entry) + "-intro")
	expect(world.population.count() == 5 and world.map.surface_at(Vector2i(25, 26)).id == &"road", "authored colony and unfinished road exist immediately")
	expect(world.tasks.slots[0] == story.episode.opening_order, "the feast or statue occupies the first slot")
	var start_time := world.match_controller.time_remaining
	await key(KEY_B)
	await key(KEY_SPACE)
	expect(screen._construction == null and is_equal_approx(world.match_controller.time_remaining, start_time), "modal dialogue blocks construction and freezes time")
	await _check_name_interruption(entry, restore)
	await _dismiss_dialogue()
	expect(story.visible and not story.is_modal and not get_tree().paused, "road hint leaves the world live")
	expect(not screen.hud.get_node("%Timer").visible and is_equal_approx(world.match_controller.time_remaining, start_time), "the live road lesson keeps the execution clock hidden and stopped")
	expect(screen.selection.selected and screen.selection.cell == ROAD_CELL, "the road lesson highlights the gap in the road")
	var hint: Label = story.get_node("%Hint")
	expect(hint.atr(hint.text) == tr("ui.story.tutorial.road_hint"), "the road hint names the highlighted tile")
	await _capture_tutorial(String(entry) + "-road")
	if not restore:
		await click(screen.hud.get_node("%TasksTab"))
		await _check_first_reprimand(entry)
		await click(screen.hud.get_node("%TasksTab"))
		expect(screen._section == &"" and not story.is_modal and hint.text == "ui.story.guided.road_only", "repeating a mistake gets only the compact reprimand")
	await key(KEY_B)
	var menu: ConstructionMenu = screen._construction
	if menu == null:
		expect(false, "B opens construction during the road hint")
		return
	await choose_building(menu, &"house")
	if restore:
		await _check_first_reprimand(entry)
		expect(screen._construction == menu and menu.visible and menu._selected == story.episode.road_option, "the tutorial restores the same construction palette and tool")
		await choose_building(menu, &"house")
	expect(menu._selected == story.episode.road_option and story.get_node("%Hint").text == "ui.story.guided.road_only", "choosing a house leaves the road tool selected")
	await click(menu.controls[&"demolish"])
	expect(menu._tool == &"build" and not world.build_controller.demolish_at(Vector2i(24, 25)), "demolition is blocked in the interface and controller")
	await choose_building(menu, &"road")
	await click_at(cell_point(ROAD_CELL + Vector2i.RIGHT))
	expect(menu.draft.size() == 0 and story.get_node("%Hint").text == "ui.story.guided.cell", "a road on the wrong tile gets a reprimand")
	expect(not world.build_controller.try_build(story.episode.road_option, ROAD_CELL + Vector2i.RIGHT), "the controller also rejects an off-guide placement")
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
	expect(screen.selection.selected and screen.selection.cell == ORDER_CELL, "the first order highlights its placement tile")
	expect(hint.atr(hint.text) == tr("ui.story.tutorial.order_hint"), "the order hint names the first request")
	await click(screen.hud.get_node("%TasksTab"))
	var category: Button = screen.hud.task_panel.get_node("%Category")
	if not category.button_pressed:
		await click(category)
	var request: TaskRequest = screen.hud.task_panel.get_node("%Requests").get_child(0)
	var other_request: TaskRequest = screen.hud.task_panel.get_node("%Requests").get_child(1)
	var other_offer: TaskOffer = other_request.get_node("%Offers").get_child(0)
	await click(other_offer.placement)
	expect(screen._construction == null and story.get_node("%Hint").text == "ui.story.guided.order_only", "another royal request gets a reprimand")
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
	expect(hint.atr(hint.text) == tr("ui.story.tutorial.order_hint"), "a correct placement dismisses the reprimand")
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
		expect(world.match_controller.countdown_suspended and not screen.hud.get_node("%Timer").visible, "a restored tutorial still holds the execution clock")
		expect(story.capture_checkpoint().get("first_reprimand_seen") == true, "the first reprimand is remembered after loading")
		await click(screen.hud.controls[&"build"])
		expect(not story.is_modal and story.get_node("%Hint").text == "ui.story.guided.impatient", "a mistake after loading stays in the compact hint")
	var time_before_order := world.match_controller.time_remaining
	await _wait_for_dialogue(story)
	var key_text := "ui.story.tutorial." + ending
	dialogue = story.get_node("%Dialogue")
	expect(tr(key_text) != key_text and dialogue.atr(dialogue.text) == tr(key_text), "the chosen variant gets its own localized closing dialogue")
	if dialogue.visible_characters != -1:
		await click(story.get_node("%Continue"))
	await _capture_tutorial(String(entry) + "-ending")
	expect(world.tasks.completed_count == 1 and world.match_controller.time_remaining > time_before_order, "the normal order adds time once")
	await _dismiss_dialogue()
	expect(not story.visible and not get_tree().paused and screen.world == world, "the same colony continues after the ending")
	expect(story.capture_checkpoint().is_empty(), "completed tutorial state is omitted from future saves")
	var clock_after_tutorial := world.match_controller.time_remaining
	await frames(12)
	expect(screen.hud.get_node("%Timer").visible and world.match_controller.time_remaining < clock_after_tutorial, "the execution clock begins only when the prologue is over")
	expect(not world.build_controller.placement_allowed.is_valid(), "ordinary construction resumes after the tutorial")

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
	for line_index in range(24):
		if not story.visible or not story.is_modal:
			return
		await click(story.get_node("%Continue"))
	expect(false, "dialogue reaches a gameplay step or ending")

func _check_name_interruption(entry: StringName, paste: bool) -> void:
	var story: StoryOverlay = screen.story
	var dialogue: Label = story.get_node("%Dialogue")
	await click(story.get_node("%Continue"))
	expect(dialogue.text == tr("ui.story.tutorial.ask_name"), "the queen asks the player's name before explaining the job")
	if dialogue.visible_characters != -1:
		await click(story.get_node("%Continue"))
	var name_window: Control = story.get_node("%NameWindow")
	var name_input: LineEdit = story.get_node("%NameInput")
	expect(name_window.is_visible_in_tree() and name_input.has_focus() and name_input.text.is_empty(), "the authored name window opens with focused empty input")
	expect(story.get_node("%Continue").disabled and get_tree().paused, "the name window keeps gameplay paused and waits for input")
	await key(KEY_ENTER)
	expect(name_window.visible and name_input.text.is_empty(), "enter without text leaves the name prompt open")
	await _capture_tutorial(String(entry) + "-name-input")
	var starting_x := name_window.position.x
	if paste:
		name_input.text = "A full pasted name"
		name_input.text_changed.emit(name_input.text)
	else:
		var typed := InputEventKey.new()
		typed.pressed = true
		typed.keycode = KEY_A
		typed.physical_keycode = KEY_A
		typed.unicode = "А".unicode_at(0)
		get_viewport().push_input(typed, true)
		typed = typed.duplicate()
		typed.pressed = false
		get_viewport().push_input(typed, true)
	await frames(1)
	expect(not name_input.editable and story.get_node("%Continue").disabled, "the first text change immediately interrupts name entry")
	await frames(4)
	expect(name_window.position.x > starting_x, "the queen swipes the name window away")
	await frames(20)
	expect(not name_window.visible and name_input.text.is_empty() and dialogue.text == tr("ui.story.tutorial.never_mind"), "the window disappears and the queen says never mind")
	if dialogue.visible_characters != -1:
		await click(story.get_node("%Continue"))
	await _capture_tutorial(String(entry) + "-never-mind")
	await click(story.get_node("%Continue"))
	expect(dialogue.text == tr("ui.story.tutorial.given_name"), "the queen assigns Shuti or Jesty herself")

func _check_first_reprimand(entry: StringName) -> void:
	var story: StoryOverlay = screen.story
	var dialogue: Label = story.get_node("%Dialogue")
	var portrait: TextureRect = story.get_node("%Portrait")
	expect(story.is_modal and get_tree().paused, "the first mistake interrupts the lesson with a dialogue")
	expect(dialogue.text == tr("ui.story.tutorial.first_reprimand"), "the queen delivers the localized first reprimand")
	expect(portrait.is_visible_in_tree() and portrait.texture != null and portrait.texture.resource_path.ends_with("ant_queen_angry.png"), "the queen appears with her angry portrait")
	if dialogue.visible_characters != -1:
		await click(story.get_node("%Continue"))
	await _capture_tutorial(String(entry) + "-first-reprimand")
	await _dismiss_dialogue()
	expect(story.guide_section() == &"build" and screen.selection.selected and screen.selection.cell == ROAD_CELL and not get_tree().paused, "closing the reprimand returns to the highlighted road")

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
