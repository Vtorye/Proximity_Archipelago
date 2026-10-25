extends Node
## Persists working settings. Presentation reads this boundary; gameplay has no dependency.
signal changed
const PATH := "user://settings.cfg"
var master_volume := 70.0
var fullscreen := false
var vsync := true
var reduced_motion := false
var show_grid := false
var _click: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		master_volume = clampf(float(config.get_value("audio", "master", 70.0)), 0.0, 100.0)
		fullscreen = bool(config.get_value("video", "fullscreen", false))
		vsync = bool(config.get_value("video", "vsync", true))
		reduced_motion = bool(config.get_value("accessibility", "reduced_motion", false))
		show_grid = bool(config.get_value("interface", "grid", false))
	_click = AudioStreamPlayer.new()
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(660 * 2)
	for index in range(660):
		var wave: float = sin(index * TAU * 720.0 / 22050.0) * exp(-index / 100.0) * 0.12
		samples.encode_s16(index * 2, int(wave * 32767.0))
	sound.data = samples
	_click.stream = sound
	add_child(_click)
	apply()

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	changed.emit()

func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "vsync", vsync)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	config.set_value("interface", "grid", show_grid)
	apply()
	return config.save(PATH)

func reset_defaults() -> void:
	master_volume = 70.0
	fullscreen = false
	vsync = true
	reduced_motion = false
	show_grid = false
	save()

func play_click() -> void:
	if _click != null and master_volume > 0.0:
		_click.play()
