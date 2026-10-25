extends MenuBase
## Native pixel controls shared by title-screen and paused-session settings.
var controls: Dictionary[StringName, Control] = {}
var _saved: Label
var _volume_value: Label

func _ready() -> void:
	if Router.current_screen_is_pausable():
		PauseController.acquire(&"settings")
	var content: VBoxContainer = ColonyStyle.modal(self, 256)
	content.add_child(ColonyStyle.label("Настройки", 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var title: Label = ColonyStyle.label("Громкость")
	title.custom_minimum_size.x = 90
	row.add_child(title)
	var slider := HSlider.new()
	slider.max_value = 100
	slider.step = 1
	slider.value = AppSettings.master_volume
	slider.custom_minimum_size = Vector2(80, 12)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	_volume_value = ColonyStyle.label("%d%%" % slider.value)
	_volume_value.custom_minimum_size.x = 22
	row.add_child(_volume_value)
	slider.value_changed.connect(func(value: float):
		AppSettings.master_volume = value
		_volume_value.text = "%d%%" % value
		_store()
		AppSettings.play_click())
	controls[&"volume"] = slider
	content.add_child(row)
	_add_toggle(content, &"fullscreen", "Полный экран", AppSettings.fullscreen)
	_add_toggle(content, &"vsync", "Вертикальная синхронизация", AppSettings.vsync)
	_add_toggle(content, &"show_grid", "Сетка клеток", AppSettings.show_grid)
	_add_toggle(content, &"reduced_motion", "Уменьшить анимацию", AppSettings.reduced_motion)
	_saved = ColonyStyle.label("Сохранено", 8, ColonyStyle.MUTED)
	content.add_child(_saved)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	var reset: Button = ColonyStyle.button("Сбросить")
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_reset)
	actions.add_child(reset)
	var done: Button = ColonyStyle.button("Готово", true)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(func(): close_requested.emit(self))
	actions.add_child(done)
	content.add_child(actions)
	controls[&"reset"] = reset
	controls[&"done"] = done
	default_focus = done

func _add_toggle(content: VBoxContainer, key: StringName, text: String, value: bool) -> void:
	var row := HBoxContainer.new()
	var title: Label = ColonyStyle.label(text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var toggle: Button = ColonyStyle.button("[X]" if value else "[ ]")
	toggle.toggle_mode = true
	toggle.button_pressed = value
	toggle.custom_minimum_size = Vector2(24, 14)
	toggle.toggled.connect(func(enabled: bool):
		toggle.text = "[X]" if enabled else "[ ]"
		AppSettings.set(key, enabled)
		_store())
	row.add_child(toggle)
	content.add_child(row)
	controls[key] = toggle

func _store() -> void:
	var error: Error = AppSettings.save()
	if _saved != null:
		_saved.text = "Сохранено" if error == OK else "Ошибка сохранения"
		_saved.add_theme_color_override("font_color", ColonyStyle.MUTED if error == OK else ColonyStyle.DANGER)

func _reset() -> void:
	AppSettings.reset_defaults()
	(controls[&"volume"] as HSlider).set_value_no_signal(AppSettings.master_volume)
	_volume_value.text = "%d%%" % AppSettings.master_volume
	for key in [&"fullscreen", &"vsync", &"show_grid", &"reduced_motion"]:
		var button: Button = controls[key] as Button
		var value: bool = bool(AppSettings.get(key))
		button.set_pressed_no_signal(value)
		button.text = "[X]" if value else "[ ]"
	_store()

func _exit_tree() -> void:
	PauseController.release(&"settings")
