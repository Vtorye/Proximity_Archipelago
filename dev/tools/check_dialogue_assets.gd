extends SceneTree

const DIALOGUES := [
	"res://visual_novel/chapters/first/first_chapter",
	"res://visual_novel/chapters/tutorial/tutorial",
	"res://visual_novel/chapters/zero/zero_chapter",
]


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
			var result := ResourceSaver.save(imported, base + ".tres")
			if result != OK:
				push_error("Cannot save %s.tres: %s" % [base, error_string(result)])
				failed = true
			continue
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
