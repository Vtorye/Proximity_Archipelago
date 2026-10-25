class_name MatchHud
extends Control
signal pause_requested
signal settings_requested
signal zoom_in_requested
signal zoom_out_requested
var world: World
var controls: Dictionary[StringName, Button] = {}
var stock_labels: Dictionary[StringName, Label] = {}
var stock_chips: Dictionary[StringName, Control] = {}
var progress: Dictionary[StringName, ProgressBar] = {}
var _timer: Label
var _ants: Label
var _zoom: Label
var _toast: Label
var _toast_time := 0.0
var _warning: Label
var _zoom_level := 2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyStyle.fill(self)
	ColonyStyle.apply(self)
	var top := PanelContainer.new()
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 8
	top.offset_bottom = 56
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)
	for type in world.inventory.registered_types():
		var chip := HBoxContainer.new()
		chip.custom_minimum_size.x = 100
		chip.add_theme_constant_override("separation", 4)
		stock_chips[type.id] = chip
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = _resource_icon(type.id)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(icon)
		var amount: Label = ColonyStyle.label("0")
		amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(amount)
		stock_labels[type.id] = amount
		row.add_child(chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_ants = ColonyStyle.label("5")
	_ants.tooltip_text = "Муравьи"
	row.add_child(_ants)
	row.add_child(ColonyStyle.label("м.", 8, ColonyStyle.MUTED))
	_timer = ColonyStyle.label("3:00", 8, ColonyStyle.ACCENT)
	_timer.custom_minimum_size.x = 48
	row.add_child(_timer)
	var pause: Button = ColonyStyle.button("||")
	pause.custom_minimum_size = Vector2(28, 28)
	pause.tooltip_text = "Пауза (Esc)"
	pause.pressed.connect(func(): pause_requested.emit())
	row.add_child(pause)
	controls[&"pause"] = pause
	var settings: Button = ColonyStyle.button("...")
	settings.custom_minimum_size = Vector2(32, 28)
	settings.tooltip_text = "Настройки"
	settings.pressed.connect(func(): settings_requested.emit())
	row.add_child(settings)
	controls[&"settings"] = settings
	var objectives := PanelContainer.new()
	objectives.position = Vector2(8, 64)
	objectives.custom_minimum_size = Vector2(168, 0)
	add_child(objectives)
	var goals := VBoxContainer.new()
	goals.add_theme_constant_override("separation", 2)
	objectives.add_child(goals)
	goals.add_child(ColonyStyle.label("Цель: по %d" % world.match_controller.target_amount, 8, ColonyStyle.MUTED))
	for type in world.match_controller.tracked_types:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		var caption: Label = ColonyStyle.label(type.display_name)
		caption.custom_minimum_size.x = 84
		line.add_child(caption)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(56, 6)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = world.match_controller.target_amount
		bar.add_theme_stylebox_override("background", ColonyStyle.box(Color("151515"), Color("555555"), 0))
		bar.add_theme_stylebox_override("fill", ColonyStyle.box(ColonyStyle.ACCENT, ColonyStyle.ACCENT, 0))
		line.add_child(bar)
		progress[type.id] = bar
		goals.add_child(line)
	_warning = ColonyStyle.label("", 8, ColonyStyle.DANGER)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size.x = 144
	goals.add_child(_warning)
	var bottom := PanelContainer.new()
	add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 8
	bottom.offset_right = -8
	bottom.offset_top = -28
	bottom.offset_bottom = -6
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 6)
	bottom.add_child(hints)
	var help: Label = ColonyStyle.label("ЛКМ: камера  ПКМ: стройка  WASD", 8, ColonyStyle.MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.add_child(help)
	for key in [&"zoom_out", &"zoom_in"]:
		var button: Button = ColonyStyle.button("-" if key == &"zoom_out" else "+")
		button.custom_minimum_size = Vector2(24, 20)
		button.pressed.connect(func():
			if key == &"zoom_out": zoom_out_requested.emit()
			else: zoom_in_requested.emit())
		hints.add_child(button)
		controls[key] = button
		if key == &"zoom_out":
			_zoom = ColonyStyle.label("1x", 8, ColonyStyle.MUTED)
			hints.add_child(_zoom)
	_toast = ColonyStyle.label("", 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", ColonyStyle.box())
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_left = 8
	_toast.offset_right = -8
	_toast.offset_top = -64
	_toast.offset_bottom = -34
	_toast.hide()
	world.inventory.changed.connect(refresh)
	world.population.changed.connect(refresh)
	world.match_controller.time_changed.connect(_on_time_changed)
	refresh()
	set_zoom(2)

func _resource_icon(id: StringName) -> Texture2D:
	return world.art.berries if id == &"food" else (world.art.timber if id == &"wood" else world.art.stone)

func refresh() -> void:
	for type in world.inventory.registered_types():
		stock_labels[type.id].text = "%d(%d)" % [world.inventory.quantity(type), world.inventory.available(type)] if type.id == &"food" else str(world.inventory.quantity(type))
		stock_chips[type.id].tooltip_text = "%s: %d, свободно %d" % [type.display_name, world.inventory.quantity(type), world.inventory.available(type)]
		if progress.has(type.id):
			progress[type.id].value = world.inventory.quantity(type)
	_ants.text = str(world.population.agents().size())
	var food: ResourceType = world.inventory.type_by_id(&"food")
	_warning.text = "Нужна пища" if world.inventory.available(food) < 3 else ""

func _on_time_changed(seconds: int) -> void:
	_timer.text = "%d:%02d" % [seconds / 60, seconds % 60]
	_timer.add_theme_color_override("font_color", ColonyStyle.DANGER if seconds <= 30 else ColonyStyle.ACCENT)

func set_zoom(value: int) -> void:
	_zoom_level = value
	_zoom.text = "%sx" % str(WorldCamera.ZOOMS[value])
	controls[&"zoom_in"].disabled = value >= WorldCamera.ZOOMS.size() - 1
	controls[&"zoom_out"].disabled = value <= 0

func lock_zoom(locked: bool) -> void:
	controls[&"zoom_in"].disabled = locked or _zoom_level >= WorldCamera.ZOOMS.size() - 1
	controls[&"zoom_out"].disabled = locked or _zoom_level <= 0

func toast(message: String, danger: bool = false) -> void:
	_toast.text = message
	_toast.add_theme_color_override("font_color", ColonyStyle.DANGER if danger else ColonyStyle.TEXT)
	_toast_time = 3.0
	_toast.show()

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.hide()
