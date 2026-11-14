extends MenuBase
## Native pixel controls shared by title-screen and paused-session settings.
var controls: Dictionary[StringName, Control] = {}
@onready var _saved: Label = %Saved
@onready var _volume_value: Label = %VolumeValue
@onready var _text_value: Label = %TextValue

func _ready() -> void:
	if Router.current_screen_is_pausable():
		PauseController.acquire(&"settings")
	ColonyStyle.apply(self)
	var slider: HSlider = %Slider
	slider.value = AppSettings.master_volume
	_volume_value.text = "%d%%" % slider.value
	slider.value_changed.connect(func(value: float):
		AppSettings.master_volume = value
		_volume_value.text = "%d%%" % value
		_store()
		AppSettings.play_click())
	controls[&"volume"] = slider
	controls[&"text_size_minus"] = %TextMinus
	%TextMinus.pressed.connect(AppSettings.play_click)
	%TextMinus.pressed.connect(_change_text_size.bind(-1))
	controls[&"text_size_plus"] = %TextPlus
	%TextPlus.pressed.connect(AppSettings.play_click)
	%TextPlus.pressed.connect(_change_text_size.bind(1))
	controls[&"reset"] = %Reset
	%Reset.pressed.connect(AppSettings.play_click)
	%Reset.pressed.connect(_reset)
	controls[&"done"] = %WindowHeader.toggle
	%WindowHeader.close_requested.connect(func(): close_requested.emit(self))
	_refresh_text_size()
	_bind_toggle(%Fullscreen, &"fullscreen")
	_bind_toggle(%Vsync, &"vsync")
	_bind_toggle(%ShowGrid, &"show_grid")
	_bind_toggle(%ReducedMotion, &"reduced_motion")
	default_focus = controls[&"done"]

func _bind_toggle(toggle: Button, key: StringName) -> void:
	var enabled: bool = AppSettings.get(key)
	toggle.text = "[X]" if enabled else "[ ]"
	toggle.set_pressed_no_signal(enabled)
	toggle.pressed.connect(AppSettings.play_click)
	toggle.toggled.connect(func(value: bool):
		toggle.text = "[X]" if value else "[ ]"
		AppSettings.set(key, value)
		_store())
	controls[key] = toggle

func _store() -> void:
	var error: Error = AppSettings.save()
	if _saved != null:
		_saved.text = "ui.settings.saved" if error == OK else "ui.settings.save_error"
		_saved.add_theme_color_override("font_color", ColonyStyle.color(&"muted") if error == OK else ColonyStyle.color(&"danger"))

func _change_text_size(delta: int) -> void:
	AppSettings.text_size += delta
	_refresh_text_size()
	_store()

func _refresh_text_size() -> void:
	_text_value.text = tr("ui.settings.text_pixels") % AppSettings.minimum_text_size()
	controls[&"text_size_minus"].disabled = AppSettings.text_size == 0
	controls[&"text_size_plus"].disabled = AppSettings.text_size == AppSettings.TYPOGRAPHY.minimum_sizes.size() - 1

func _reset() -> void:
	AppSettings.reset_defaults()
	(controls[&"volume"] as HSlider).set_value_no_signal(AppSettings.master_volume)
	_volume_value.text = "%d%%" % AppSettings.master_volume
	_refresh_text_size()
	for key in [&"fullscreen", &"vsync", &"show_grid", &"reduced_motion"]:
		var button: Button = controls[key] as Button
		var value: bool = bool(AppSettings.get(key))
		button.set_pressed_no_signal(value)
		button.text = "[X]" if value else "[ ]"
	_store()

func _exit_tree() -> void:
	PauseController.release(&"settings")
