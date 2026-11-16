class_name PauseMenu
extends MenuBase
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	%WindowHeader.close_requested.connect(func(): close_requested.emit(self))
	controls[&"resume"] = %Resume
	%Resume.pressed.connect(AppSettings.play_click)
	%Resume.pressed.connect(PauseController.resume)
	controls[&"save"] = %Save
	%Save.pressed.connect(AppSettings.play_click)
	%Save.pressed.connect(_save)
	controls[&"restart"] = %Restart
	%Restart.pressed.connect(AppSettings.play_click)
	%Restart.pressed.connect(_restart)
	controls[&"settings"] = %Settings
	%Settings.pressed.connect(AppSettings.play_click)
	%Settings.pressed.connect(_open_settings)
	controls[&"main"] = %MainMenu
	%MainMenu.pressed.connect(AppSettings.play_click)
	%MainMenu.pressed.connect(_quit_to_menu)
	default_focus = %Resume

func _save() -> void:
	var current: Node = Router._current
	if current != null and current.get("world") is World:
		var error: Error = SessionSave.write(current.world)
		%Save.text = "ui.voyage.saved" if error == OK else "ui.voyage.save_failed"

func _open_settings() -> void:
	# Nested overlay: sits on top of the pause menu
	Router.push_overlay(&"settings")

func _restart() -> void:
	Router.restart_current()

func _quit_to_menu() -> void:
	# Explicitly unpause before navigating away through the owning pause boundary.
	Router.goto(&"main_menu")
