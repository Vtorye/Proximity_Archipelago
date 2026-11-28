extends "res://dev/tests/ui_runner.gd"
## Exercise every authored spoken line at both ends of the text-size setting.

@onready var story: StoryOverlay = $Story

func _run() -> void:
	# This matrix measures layout; the gameplay runner exercises dialogue audio.
	story.get_node("%Voice").stream = null
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
