extends MenuBase
## Native pixel controls shared by title-screen and paused-session settings.
var controls: Dictionary[StringName, Control] = {}
var _dragging_volume := false
var _volume_pending := false
@onready var _saved: Label = %Saved
@onready var _volume_value: Label = %VolumeValue
@onready var _text_value: Label = %TextValue
@onready var _volume_save_timer: Timer = $VolumeSaveTimer

func _ready() -> void:
	if Router.current_screen_is_pausable():
		PauseController.acquire(&"settings")
	var slider: HSlider = %Slider
	slider.value = AppSettings.master_volume
	_volume_value.text = "%d%%" % slider.value
	slider.value_changed.connect(_change_volume)
	slider.drag_started.connect(_begin_volume_drag)
	slider.drag_ended.connect(_end_volume_drag)
	_volume_save_timer.timeout.connect(_store)
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
	_bind_toggle(%ShowGrid, &"show_grid")
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

func _change_volume(value: float) -> void:
	AppSettings.master_volume = value
	AppSettings.apply()
	_volume_value.text = "%d%%" % value
	_volume_pending = true
	_saved.text = ""
	if not _dragging_volume:
		_volume_save_timer.start()
	AppSettings.play_click()

func _begin_volume_drag() -> void:
	_dragging_volume = true
	_volume_save_timer.stop()

func _end_volume_drag(_value_changed: bool) -> void:
	_dragging_volume = false
	if _volume_pending:
		_store()

func _store() -> void:
	_volume_save_timer.stop()
	_show_save_result(AppSettings.save())

func _show_save_result(error: Error) -> void:
	if error == OK:
		_volume_pending = false
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
	_volume_save_timer.stop()
	_show_save_result(AppSettings.reset_defaults())
	(controls[&"volume"] as HSlider).set_value_no_signal(AppSettings.master_volume)
	_volume_value.text = "%d%%" % AppSettings.master_volume
	_refresh_text_size()
	for key in [&"fullscreen", &"show_grid"]:
		var button: Button = controls[key] as Button
		var value: bool = bool(AppSettings.get(key))
		button.set_pressed_no_signal(value)
		button.text = "[X]" if value else "[ ]"

func _exit_tree() -> void:
	if _volume_pending:
		var error := AppSettings.save()
		if error != OK:
			push_warning("Could not save volume preference: %s" % error_string(error))
	PauseController.release(&"settings")
