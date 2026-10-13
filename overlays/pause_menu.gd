extends MenuBase

@onready var _resume: Button   = $CenterContainer/PanelContainer/VBoxContainer/ResumeButton
@onready var _settings: Button = $CenterContainer/PanelContainer/VBoxContainer/SettingsButton
@onready var _quit: Button     = $CenterContainer/PanelContainer/VBoxContainer/QuitButton

func _ready() -> void:
	_resume.pressed.connect(PauseController.resume)
	_settings.pressed.connect(_open_settings)
	_quit.pressed.connect(_quit_to_menu)

func _open_settings() -> void:
	# Nested overlay: sits on top of the pause menu
	var settings := Router.push_overlay(&"settings")
	if settings:
		settings.closed.connect(func(): pass)  # optional hook

func _quit_to_menu() -> void:
	# Explicitly unpause before navigating away
	get_tree().paused = false
	Router.goto(&"main_menu")
