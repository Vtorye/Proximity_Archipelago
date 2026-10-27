extends MenuBase
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	var content: VBoxContainer = ColonyStyle.modal(self, 144)
	content.add_child(ColonyStyle.label("Пауза", 12))
	var resume: Button = ColonyStyle.button("Продолжить", true)
	resume.pressed.connect(PauseController.resume)
	content.add_child(resume)
	controls[&"resume"] = resume
	var restart: Button = ColonyStyle.button("Заново")
	restart.pressed.connect(_restart)
	content.add_child(restart)
	controls[&"restart"] = restart
	var settings: Button = ColonyStyle.button("Настройки")
	settings.pressed.connect(_open_settings)
	content.add_child(settings)
	controls[&"settings"] = settings
	var main: Button = ColonyStyle.button("В меню")
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
