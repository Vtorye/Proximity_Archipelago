extends MenuBase
## The same settings panel opens from the main menu or an active paused session.
var controls: Dictionary[StringName, Control] = {}
var _saved: Label
var _volume_value: Label

func _ready() -> void:
	if Router.current_screen_is_pausable():
		PauseController.acquire(&"settings")
	var content: VBoxContainer = ColonyStyle.modal(self, 560)
	content.add_child(ColonyStyle.label("ВАША КОЛОНИЯ · ВАШИ ПРАВИЛА", 12, ColonyStyle.ACCENT))
	content.add_child(ColonyStyle.label("Настройки", 30))
	content.add_child(ColonyStyle.label("Изменения применяются сразу и сохраняются.", 15, ColonyStyle.MUTED))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 20)
	var volume_title: Label = ColonyStyle.label("Громкость", 18)
	volume_title.custom_minimum_size.x = 210
	volume_row.add_child(volume_title)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = AppSettings.master_volume
	slider.custom_minimum_size.x = 160
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "Громкость звуков интерфейса"
	volume_row.add_child(slider)
	var volume_value: Label = ColonyStyle.label("%d%%" % slider.value, 16, ColonyStyle.ACCENT)
	volume_value.custom_minimum_size.x = 48
	_volume_value = volume_value
	volume_row.add_child(volume_value)
	slider.value_changed.connect(func(value: float):
		AppSettings.master_volume = value
		volume_value.text = "%d%%" % value
		_store()
		AppSettings.play_click())
	content.add_child(volume_row)
	controls[&"volume"] = slider
	_add_toggle(content, &"fullscreen", "Полный экран", AppSettings.fullscreen)
	_add_toggle(content, &"vsync", "Вертикальная синхронизация", AppSettings.vsync)
	_add_toggle(content, &"show_grid", "Сетка клеток", AppSettings.show_grid)
	_add_toggle(content, &"reduced_motion", "Уменьшить анимацию", AppSettings.reduced_motion)
	content.add_child(ColonyStyle.label("Esc — назад · Tab — переход между настройками", 14, ColonyStyle.MUTED))
	_saved = ColonyStyle.label("Все изменения сохранены", 14, ColonyStyle.GREEN)
	content.add_child(_saved)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
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
	var title: Label = ColonyStyle.label(text, 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var toggle := CheckButton.new()
	toggle.button_pressed = value
	toggle.custom_minimum_size = Vector2(76, 42)
	toggle.tooltip_text = text
	toggle.toggled.connect(func(enabled: bool):
		AppSettings.set(key, enabled)
		_store())
	row.add_child(toggle)
	content.add_child(row)
	controls[key] = toggle

func _store() -> void:
	var error: Error = AppSettings.save()
	if _saved != null:
		_saved.text = "Все изменения сохранены" if error == OK else "Не удалось сохранить настройки"
		_saved.add_theme_color_override("font_color", ColonyStyle.GREEN if error == OK else ColonyStyle.DANGER)

func _reset() -> void:
	AppSettings.reset_defaults()
	(controls[&"volume"] as HSlider).set_value_no_signal(AppSettings.master_volume)
	for key in [&"fullscreen", &"vsync", &"show_grid", &"reduced_motion"]:
		(controls[key] as CheckButton).set_pressed_no_signal(bool(AppSettings.get(key)))
	_volume_value.text = "%d%%" % AppSettings.master_volume
	_store()

func _exit_tree() -> void:
	PauseController.release(&"settings")
