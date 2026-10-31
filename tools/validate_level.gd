extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "res://game/worlds/wolrd_1.tscn"
	var errors: Array[String] = LevelValidator.validate(path)
	for error in errors: print(error)
	print("LEVEL VALIDATION ", "PASS" if errors.is_empty() else "FAIL", ": ", path)
	quit(0 if errors.is_empty() else 1)
