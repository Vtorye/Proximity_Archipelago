extends MenuBase
## Native pixel controls shared by title-screen and paused-session settings.
var controls: Dictionary[StringName, Control] = {}
var _saved: Label
var _volume_value: Label
var _scale_value: Label

func _ready() -> void:
	if Router.current_screen_is_pausable():
		PauseController.acquire(&"settings")
	var content: VBoxContainer = ColonyStyle.modal(self, 256)
	content.add_child(ColonyStyle.label("Настройки", 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var title: Label = ColonyStyle.label("Громкость")
	title.custom_minimum_size.x = 180
	row.add_child(title)
	var slider := HSlider.new()
	slider.max_value = 100
	slider.step = 1
	slider.value = AppSettings.master_volume
	slider.custom_minimum_size = Vector2(160, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	_volume_value = ColonyStyle.label("%d%%" % slider.value)
	_volume_value.custom_minimum_size.x = 44
	row.add_child(_volume_value)
	slider.value_changed.connect(func(value: float):
		AppSettings.master_volume = value
		_volume_value.text = "%d%%" % value
		_store()
		AppSettings.play_click())
	controls[&"volume"] = slider
	content.add_child(row)
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 8)
	var scale_title: Label = ColonyStyle.label("Масштаб интерфейса")
	scale_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_title)
	for key in [&"ui_scale_minus", &"ui_scale_plus"]:
		var button: Button = ColonyStyle.button("-" if key == &"ui_scale_minus" else "+")
		button.custom_minimum_size = Vector2(32, 28)
		button.pressed.connect(_change_scale.bind(-0.25 if key == &"ui_scale_minus" else 0.25))
		scale_row.add_child(button)
		controls[key] = button
		if key == &"ui_scale_minus":
			_scale_value = ColonyStyle.label("")
			_scale_value.custom_minimum_size.x = 44
			_scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			scale_row.add_child(_scale_value)
	content.add_child(scale_row)
	_refresh_scale()
	_add_toggle(content, &"fullscreen", "Полный экран", AppSettings.fullscreen)
	_add_toggle(content, &"vsync", "Вертикальная синхронизация", AppSettings.vsync)
	_add_toggle(content, &"show_grid", "Сетка клеток", AppSettings.show_grid)
	_add_toggle(content, &"reduced_motion", "Уменьшить анимацию", AppSettings.reduced_motion)
	_saved = ColonyStyle.label("Сохранено", 8, ColonyStyle.MUTED)
	content.add_child(_saved)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
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
	toggle.custom_minimum_size = Vector2(48, 28)
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

func _change_scale(delta: float) -> void:
	AppSettings.ui_scale = clampf(AppSettings.ui_scale + delta, AppSettings.MIN_UI_SCALE, AppSettings.MAX_UI_SCALE)
	_refresh_scale()
	_store()

func _refresh_scale() -> void:
	_scale_value.text = "%d%%" % roundi(AppSettings.ui_scale * 100)
	controls[&"ui_scale_minus"].disabled = AppSettings.ui_scale <= AppSettings.MIN_UI_SCALE
	controls[&"ui_scale_plus"].disabled = AppSettings.ui_scale >= AppSettings.MAX_UI_SCALE

func _reset() -> void:
	AppSettings.reset_defaults()
	(controls[&"volume"] as HSlider).set_value_no_signal(AppSettings.master_volume)
	_volume_value.text = "%d%%" % AppSettings.master_volume
	_refresh_scale()
	for key in [&"fullscreen", &"vsync", &"show_grid", &"reduced_motion"]:
		var button: Button = controls[key] as Button
		var value: bool = bool(AppSettings.get(key))
		button.set_pressed_no_signal(value)
		button.text = "[X]" if value else "[ ]"
	_store()

func _exit_tree() -> void:
	PauseController.release(&"settings")
