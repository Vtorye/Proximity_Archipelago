extends MenuBase
## Native pixel controls shared by title-screen and paused-session settings.
var controls: Dictionary[StringName, Control] = {}
@onready var _saved: Label = %Saved
@onready var _volume_value: Label = %VolumeValue
@onready var _scale_value: Label = %ScaleValue

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
	controls[&"ui_scale_minus"] = %ScaleMinus
	%ScaleMinus.pressed.connect(AppSettings.play_click)
	%ScaleMinus.pressed.connect(_change_scale.bind(-0.25))
	controls[&"ui_scale_plus"] = %ScalePlus
	%ScalePlus.pressed.connect(AppSettings.play_click)
	%ScalePlus.pressed.connect(_change_scale.bind(0.25))
	controls[&"reset"] = %Reset
	%Reset.pressed.connect(AppSettings.play_click)
	%Reset.pressed.connect(_reset)
	controls[&"done"] = %Done
	%Done.pressed.connect(AppSettings.play_click)
	%Done.pressed.connect(func(): close_requested.emit(self))
	_refresh_scale()
	_bind_toggle(%Fullscreen, &"fullscreen")
	_bind_toggle(%Vsync, &"vsync")
	_bind_toggle(%ShowGrid, &"show_grid")
	_bind_toggle(%ReducedMotion, &"reduced_motion")
	default_focus = %Done

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
