extends MenuBase
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	var content: VBoxContainer = ColonyStyle.modal(self, 144)
	content.add_child(ColonyStyle.label("ui.pause.title", 12))
	var resume: Button = ColonyStyle.button("ui.pause.resume", true)
	resume.pressed.connect(PauseController.resume)
	content.add_child(resume)
	controls[&"resume"] = resume
	var restart: Button = ColonyStyle.button("ui.pause.restart")
	restart.pressed.connect(_restart)
	content.add_child(restart)
	controls[&"restart"] = restart
	var settings: Button = ColonyStyle.button("ui.menu.settings")
	settings.pressed.connect(_open_settings)
	content.add_child(settings)
	controls[&"settings"] = settings
	var main: Button = ColonyStyle.button("ui.common.main_menu")
	main.pressed.connect(_quit_to_menu)
	content.add_child(main)
	controls[&"main"] = main
	default_focus = resume

func _open_settings() -> void:
	# Nested overlay: sits on top of the pause menu
	Router.push_overlay(&"settings")

func _restart() -> void:
	Router.goto(&"match")

func _quit_to_menu() -> void:
	# Explicitly unpause before navigating away through the owning pause boundary.
	Router.goto(&"main_menu")
