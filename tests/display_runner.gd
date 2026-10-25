extends Node
## Records native fullscreen changes as rendered PNG frames, allowing viewport resizing.
var _output: String
var _frames: String
var _index := 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_output = OS.get_environment("COLONY_EVIDENCE_DIR")
	_frames = OS.get_environment("COLONY_DISPLAY_FRAMES")
	DirAccess.make_dir_recursive_absolute(_frames)
	_run.call_deferred()

func frames(count: int) -> void:
	for frame in range(count):
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(_frames.path_join("frame-%04d.png" % _index))
		_index += 1

func click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames(4)

func _run() -> void:
	AppSettings.reset_defaults()
	var boot: Node = load("res://boot.tscn").instantiate()
	get_tree().root.add_child(boot)
	await frames(30)
	await click(Router._current.controls[&"settings"])
	await frames(12)
	var settings: MenuBase = Router.top_overlay()
	await click(settings.controls[&"fullscreen"])
	await frames(30)
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		_failures.append("fullscreen control did not change native window mode")
	get_viewport().get_texture().get_image().save_png(_output.path_join("27-fullscreen-settings.png"))
	await click(settings.controls[&"fullscreen"])
	await frames(30)
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		_failures.append("fullscreen control did not restore windowed mode")
	get_viewport().get_texture().get_image().save_png(_output.path_join("28-windowed-settings.png"))
	AppSettings.reset_defaults()
	var report := {"failures": _failures, "recorded_frames": _index, "fullscreen_toggle": _failures.is_empty()}
	FileAccess.open(_output.path_join("display-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("DISPLAY REPORT ", JSON.stringify(report))
	get_tree().quit(0 if _failures.is_empty() else 1)
