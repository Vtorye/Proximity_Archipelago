extends Screen

@onready var _play: Button     = $CenterContainer/VBoxContainer/PlayButton
@onready var _settings: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var _quit: Button     = $CenterContainer/VBoxContainer/QuitButton

func _ready() -> void:
	_play.pressed.connect(func(): Router.goto(&"match", {"level_id": "mission_01"}))
	_settings.pressed.connect(func(): Router.goto(&"settings"))
	_quit.pressed.connect(func(): get_tree().quit())

func on_focus() -> void:
	_play.grab_focus()
