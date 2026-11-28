extends "res://dev/tests/ui_runner.gd"
## Exercise every authored spoken line at both ends of the text-size setting.

@onready var story: StoryOverlay = $Story

func _run() -> void:
	# This matrix measures layout; the gameplay runner exercises dialogue audio.
	story.get_node("%Voice").stream = null
	_check_editor_portrait_preview()
	await _check_static_portrait_alignment()
	await _check_portrait_scenes()
	for rules: FirstChapterRules in [preload("res://visual_novel/chapters/zero/zero_chapter_rules.tres"), preload("res://visual_novel/chapters/first/first_chapter_rules.tres")]:
		story.characters = rules.characters
		story.dialogue_resource = rules.dialogue
		story.set_lesson_skip(rules is ZeroChapterRules)
		await _measure_dialogue(rules.resource_path.get_file().get_basename())
	story.finish()
	AppSettings.language = "ru"
	AppSettings.apply()
	story.play("intro")
	await frames(4)
	story._reveal_line()
	story._advance()
	await frames(4)
	story._reveal_line()
	expect(story.get_node("%Dialogue").text == "Так… как тебя назвать…", "the queen is choosing a name")
	var name_labels := story.get_node("%NameWindow").find_children("*", "Label", true, false)
	expect(name_labels.filter(func(label: Label) -> bool: return label.text == "ui.story.name.title").size() == 1, "the name input has only one title")
	var entry: LineEdit = story.get_node("%NameInput")
	entry.text = "А"
	entry.text_changed.emit(entry.text)
	await story.get_node("%NameBeat").timeout
	await story._name_tween.finished
	await frames(4)
	expect(story.get_node("%Dialogue").text == "О, придумала!" and not story.get_node("%NameWindow").visible, "the first typed character triggers the queen's naming idea")
	story.finish()
	story.queue_free()
	await frames(8)
	print("STORY TYPOGRAPHY ", assertions, " assertions, ", failures.size(), " failures")
	get_tree().quit.call_deferred(0 if failures.is_empty() else 1)

func _check_editor_portrait_preview() -> void:
	var authored_overlay := load(story.scene_file_path) as PackedScene
	var preview_overlay := authored_overlay.instantiate()
	var frame := preview_overlay.get_node_or_null("%CharacterPortraitFrame") as Control
	var preview := preview_overlay.get_node_or_null("%WorkerPortraitEditorPreview") as Control
	expect(frame != null and frame.get_parent().name == &"DialogueWindow"
		and preview != null and preview.get_parent() == frame and preview.visible,
		"the dialogue window has one portrait frame with a visible worker preview")
	expect(preview != null and preview.get_script() == preload("res://visual_novel/portraits/static_portrait.gd"),
		"the editor preview inherits the portrait's alignment script")
	expect(story.get_node_or_null("%WorkerPortraitEditorPreview") == null, "the worker preview is removed at runtime")
	preview_overlay.free()

func _check_static_portrait_alignment() -> void:
	var scene := preload("res://visual_novel/portraits/worker/portrait.tscn")
	var portrait := scene.instantiate() as Control
	add_child(portrait)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var picture := portrait.get_node_or_null("Image") as TextureRect
	expect(picture != null, "the worker portrait has an aligned image inside its frame")
	if picture != null:
		portrait.size = Vector2(100, 180)
		await frames(3)
		expect(picture.position.x == 0.0 and is_equal_approx(picture.get_rect().end.y, portrait.size.y),
			"a wide picture aligns to the bottom and left")
		var tall_texture := GradientTexture2D.new()
		tall_texture.width = 80
		tall_texture.height = 160
		portrait.set("texture", tall_texture)
		portrait.size = Vector2(180, 100)
		await frames(3)
		expect(picture.position.x == 0.0 and is_equal_approx(picture.get_rect().end.y, portrait.size.y),
			"a tall replacement aligns to the bottom and left")
		expect(picture.size.is_equal_approx(Vector2(50, 100)), "a replacement texture keeps its own aspect ratio")
	portrait.queue_free()

func _check_portrait_scenes() -> void:
	var rules: FirstChapterRules = preload("res://visual_novel/chapters/zero/zero_chapter_rules.tres")
	var queen := rules.characters[0].duplicate() as StoryCharacter
	var courier: StoryCharacter
	for character in rules.characters:
		if character.id == &"Courier":
			courier = character.duplicate() as StoryCharacter
	expect(queen.get("default_portrait") is PackedScene, "the queen has an editor-authored default portrait scene")
	if not queen.get("default_portrait") is PackedScene:
		return
	var animations: Dictionary[StringName, PackedScene] = {&"thinking": preload("res://dev/tests/animated_portrait.tscn")}
	queen.set("portraits", animations)
	var courier_portraits: Dictionary[StringName, PackedScene] = {&"thinking": courier.get("default_portrait")}
	courier.set("portraits", courier_portraits)
	story.characters = [queen, courier]
	story.dialogue_resource = DialogueManager.create_resource_from_text(
		"~ intro\nQueen: First [#portrait=thinking]\nQueen: Second [#portrait=thinking]\nCourier: Third [#portrait=thinking]\nQueen: Fourth [#portrait=missing]\n=> END"
	) as DialogueResource
	story.play("intro")
	await frames(4)
	var slot: Control = story.get_node("%CharacterPortraitFrame")
	var animated := slot.get_node_or_null("AnimatedPortrait") as Control
	expect(animated != null and get_tree().paused, "the assigned portrait scene appears while the world is paused")
	if animated == null:
		story.finish()
		return
	expect(animated.get_rect() == Rect2(Vector2.ZERO, slot.size), "the live portrait fills the size frame")
	var player: AnimationPlayer = animated.get_node("AnimationPlayer")
	var before := player.current_animation_position
	await frames(4)
	expect(player.current_animation_position > before, "animation advances during dialogue pause")
	story._reveal_line()
	story._advance()
	await frames(4)
	expect(slot.get_child(0) == animated, "consecutive lines keep the same portrait instance")
	story.get_node("%DialogueHeader").set_collapsed(true)
	expect(not animated.is_visible_in_tree(), "collapsing dialogue hides the portrait")
	story.get_node("%DialogueHeader").set_collapsed(false)
	expect(animated.is_visible_in_tree(), "expanding dialogue restores the portrait")
	story._reveal_line()
	story._advance()
	await frames(4)
	expect(not is_instance_valid(animated) and slot.get_child(0).scene_file_path == courier.get("default_portrait").resource_path,
		"the same tag resolves to the next speaker's scene and releases the old one")
	story._reveal_line()
	story._advance()
	await frames(4)
	expect(slot.get_child(0).scene_file_path == queen.get("default_portrait").resource_path,
		"an unknown tag falls back to the speaker's default scene")
	story.finish()
	await frames(2)
	expect(slot.get_child_count() == 0 and not get_tree().paused, "finishing releases the portrait and unpauses the world")

func _measure_dialogue(chapter: String) -> void:
	var lines: Dictionary = story.dialogue_resource.lines
	for locale: String in ["ru", "en"]:
		AppSettings.language = locale
		for size: int in [0, AppSettings.TYPOGRAPHY.minimum_sizes.size() - 1]:
			AppSettings.text_size = size
			AppSettings.apply()
			story.theme = ColonyStyle.theme_for_text_size(size)
			var longest := ""
			var tallest := 0.0
			var worst_overflow := 0.0
			for id: String in lines:
				var definition: Dictionary = lines[id]
				if definition.get("type") != "dialogue" or Array(definition.get("tags", [])).any(func(tag: String) -> bool: return tag.begins_with("action=")):
					continue
				story.finish()
				story.play(id)
				await frames(5)
				var typing_height: float = story.get_node("%DialogueWindow").size.y
				story._reveal_line()
				await frames(4)
				var scroll: ScrollContainer = story.get_node("%Scroll")
				var bar := scroll.get_v_scroll_bar()
				var overflow := maxf(0.0, bar.max_value - bar.page)
				worst_overflow = maxf(worst_overflow, overflow)
				expect(overflow <= 1.0 if size == 0 else overflow <= bar.page * 0.5, "%s size %d fits dialogue %s without excessive scrolling" % [locale, size, definition.text])
				var window: Control = story.get_node("%DialogueWindow")
				expect(get_viewport().get_visible_rect().encloses(window.get_global_rect()), "dialogue and buttons stay inside the viewport")
				expect(absf(typing_height - window.size.y) <= 1.0, "revealing letters does not resize %s (%s → %s)" % [definition.text, typing_height, window.size.y])
				var label: Label = story.get_node("%Dialogue")
				var slot: Control = story.get_node("%CharacterPortraitFrame")
				expect(slot.get_global_rect().end.x <= label.get_global_rect().position.x, "the portrait stays beside the text")
				if label.get_minimum_size().y > tallest:
					tallest = label.get_minimum_size().y
					longest = id
			story.finish()
			story.play(longest)
			await frames(5)
			story._reveal_line()
			await frames(4)
			expect(story.get_node("%DialogueHeader").handle.text != "ui.chapter.conversations", "only the character name remains in the dialogue header")
			if DisplayServer.get_name() != "headless":
				await capture("%s-%s-size-%d" % [chapter, locale, size], 1)
			print("DIALOGUE FIT ", locale, " size ", size, " tallest ", tallest, " overflow ", worst_overflow)
