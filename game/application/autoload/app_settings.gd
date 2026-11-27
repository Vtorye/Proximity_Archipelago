extends Node
## Persists working settings. Presentation reads this boundary; gameplay has no dependency.
signal text_size_changed
signal language_changed
signal grid_visibility_changed
const PATH := "user://settings.cfg"
@export var defaults: AppDefaults = preload("res://game/application/app_defaults.tres")
var master_volume: float
var fullscreen: bool
var show_grid: bool
## Empty keeps the system locale until the player chooses a language.
var language := ""
const TYPOGRAPHY: UiTypography = ColonyStyle.TYPOGRAPHY
var text_size: int = clampi(TYPOGRAPHY.default_index, 0, TYPOGRAPHY.minimum_sizes.size() - 1):
	set(value):
		text_size = clampi(value, 0, TYPOGRAPHY.minimum_sizes.size() - 1)
@onready var _click: AudioStreamPlayer = $Click
var _applied_text_size := text_size
var _applied_show_grid := show_grid

func _ready() -> void:
	master_volume = defaults.master_volume
	fullscreen = defaults.fullscreen
	show_grid = defaults.show_grid
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		language = str(config.get_value("interface", "language", ""))
		if language not in ["en", "ru"]:
			language = ""
		master_volume = clampf(float(config.get_value("audio", "master", defaults.master_volume)), 0.0, 100.0)
		fullscreen = bool(config.get_value("video", "fullscreen", defaults.fullscreen))
		show_grid = bool(config.get_value("interface", "grid", defaults.show_grid))
		var migrated: int = TYPOGRAPHY.default_index
		if config.has_section_key("interface", "scale"):
			var legacy: float = float(config.get_value("interface", "scale"))
			migrated = roundi((legacy - 0.5) / 0.25)
		text_size = int(config.get_value("interface", "text_size", migrated))
	apply()

func minimum_text_size() -> int:
	return TYPOGRAPHY.minimum_sizes[text_size]

func apply() -> void:
	var locale_changed := not language.is_empty() and TranslationServer.get_locale() != language
	if locale_changed:
		TranslationServer.set_locale(language)
	var volume_db := linear_to_db(maxf(master_volume / 100.0, 0.0001))
	if not is_equal_approx(AudioServer.get_bus_volume_db(0), volume_db):
		AudioServer.set_bus_volume_db(0, volume_db)
	var mute := master_volume <= 0.0
	if AudioServer.is_bus_mute(0) != mute:
		AudioServer.set_bus_mute(0, mute)
	if DisplayServer.get_name() != "headless":
		var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		var was_fullscreen: bool = mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if fullscreen != was_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if _applied_text_size != text_size:
		_applied_text_size = text_size
		text_size_changed.emit()
	if _applied_show_grid != show_grid:
		_applied_show_grid = show_grid
		grid_visibility_changed.emit()
	if locale_changed:
		language_changed.emit()

func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("interface", "grid", show_grid)
	config.set_value("interface", "text_size", text_size)
	config.set_value("interface", "language", language)
	apply()
	return config.save(PATH)

func reset_defaults() -> Error:
	master_volume = defaults.master_volume
	fullscreen = defaults.fullscreen
	show_grid = defaults.show_grid
	text_size = TYPOGRAPHY.default_index
	return save()

func play_click() -> void:
	if _click != null and master_volume > 0.0:
		_click.play()

var quitting := false

func stop_audio() -> void:
	if is_instance_valid(_click):
		_click.stop()
		_click.stream = null

func quit_game() -> void:
	if quitting:
		return
	quitting = true
	stop_audio()
	# Let the audio server retire queued playback before destroying the application.
	await get_tree().create_timer(0.05, true).timeout
	get_tree().quit()

func _exit_tree() -> void:
	stop_audio()
