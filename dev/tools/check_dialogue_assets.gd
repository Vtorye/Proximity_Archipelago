extends SceneTree

const FIRST_RULES := "res://visual_novel/chapters/first/first_chapter_rules.tres"
const DIALOGUES := {
	"res://visual_novel/chapters/first/first_chapter": FIRST_RULES,
	"res://visual_novel/chapters/tutorial/tutorial": FIRST_RULES,
	"res://visual_novel/chapters/zero/zero_chapter": "res://visual_novel/chapters/zero/zero_chapter_rules.tres",
}


func _initialize() -> void:
	var write := "--write" in OS.get_cmdline_user_args()
	var failed := false
	for base: String in DIALOGUES:
		var imported := load(base + ".dialogue") as DialogueResource
		if imported == null:
			push_error("Dialogue import is missing or invalid: " + base + ".dialogue")
			failed = true
			continue
		if write:
			var path := base + ".tres"
			var uid := ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID
			var result := ResourceSaver.save(imported, path)
			if result == OK and uid != ResourceUID.INVALID_ID:
				result = ResourceSaver.set_uid(path, uid)
			if result != OK:
				push_error("Cannot save %s: %s" % [path, error_string(result)])
				failed = true
			continue
		if not _check_portrait_tags(base, imported, load(DIALOGUES[base]) as FirstChapterRules):
			failed = true
		var saved := load(base + ".tres") as DialogueResource
		if saved == null or saved.cues != imported.cues or saved.lines != imported.lines \
				or saved.first_cue != imported.first_cue or saved.using_states != imported.using_states \
				or saved.character_names != imported.character_names:
			push_error("Dialogue asset is out of date: %s.tres. Run this script with -- --write." % base)
			failed = true
	if not write and not ResourceLoader.load("res://game/match/match.tscn") is PackedScene:
		push_error("Cannot load the match scene.")
		failed = true
	quit(1 if failed else 0)


func _check_portrait_tags(base: String, dialogue: DialogueResource, rules: FirstChapterRules) -> bool:
	if rules == null:
		push_error("Cannot load chapter rules to validate portraits: " + base + ".dialogue")
		return false
	var characters: Dictionary[StringName, StoryCharacter] = {}
	for character in rules.characters:
		characters[character.id] = character
	var valid := true
	for id: String in dialogue.lines:
		var line: Dictionary = dialogue.lines[id]
		for tag: String in line.get("tags", PackedStringArray()):
			if tag != "portrait" and not tag.begins_with("portrait="):
				continue
			var emotion := &"" if tag == "portrait" else StringName(tag.trim_prefix("portrait=").strip_edges())
			var speaker := StringName(line.get("character", ""))
			var character: StoryCharacter = characters.get(speaker)
			if not emotion.is_empty() and character != null and character.portraits.get(emotion) != null:
				continue
			push_error("%s.dialogue (line ID %s): unknown portrait tag '%s' for speaker '%s'." % [base, id, emotion, speaker])
			valid = false
	return valid
