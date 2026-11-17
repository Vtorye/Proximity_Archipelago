extends Screen
## Main menu contains only the animated background and unframed actions.
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	var has_save: bool = not SessionSave.read().is_empty()
	%Continue.visible = has_save
	controls[&"play"] = %Play
	%Play.pressed.connect(AppSettings.play_click)
	%Play.pressed.connect(_start_match.bind(false))
	controls[&"waves"] = %Waves
	%Waves.pressed.connect(AppSettings.play_click)
	%Waves.pressed.connect(_start_match.bind(true))
	controls[&"maps"] = %Maps
	%Maps.pressed.connect(AppSettings.play_click)
	%Maps.pressed.connect(func(): Router.goto(&"level_editor"))
	controls[&"tutorial"] = %Tutorial
	%Tutorial.pressed.connect(AppSettings.play_click)
	%Tutorial.pressed.connect(func(): Router.goto(&"match", {"tutorial": true}))
	controls[&"settings"] = %Settings
	%Settings.pressed.connect(AppSettings.play_click)
	%Settings.pressed.connect(func(): Router.push_overlay(&"settings"))
	controls[&"language"] = %Language
	%Language.pressed.connect(AppSettings.play_click)
	%Language.pressed.connect(_toggle_language)
	controls[&"quit"] = %Quit
	%Quit.pressed.connect(AppSettings.quit_game)
	if has_save:
		controls[&"continue"] = %Continue
		%Continue.pressed.connect(AppSettings.play_click)
		%Continue.pressed.connect(_continue)

func _start_match(waves: bool) -> void:
	var layout: Dictionary = LevelStore.load_level(LevelStore.starting_level(waves))
	if not waves and layout.is_empty():
		Router.goto(&"match", {"tutorial": true})
		return
	layout["wave_mode"] = waves
	Router.goto(&"match", layout)

func _continue() -> void:
	var saved: Dictionary = SessionSave.read()
	if not saved.is_empty():
		var layout: Dictionary = saved.layout.duplicate()
		layout["snapshot"] = saved
		Router.goto(&"match", layout)

func on_focus() -> void:
	controls[&"play"].grab_focus()

func _toggle_language() -> void:
	AppSettings.language = "en" if TranslationServer.get_locale().begins_with("ru") else "ru"
	var error := AppSettings.save()
	if error != OK:
		push_warning("Could not save language preference: %s" % error_string(error))
