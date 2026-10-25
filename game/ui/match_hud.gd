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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyStyle.fill(self)
	ColonyStyle.apply(self)
	var top := PanelContainer.new()
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 16
	top.offset_bottom = 94
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 148
	brand.add_child(ColonyStyle.label("PROXIMITY", 17, ColonyStyle.ACCENT))
	brand.add_child(ColonyStyle.label("Колония / 01", 13, ColonyStyle.MUTED))
	row.add_child(brand)
	for type in world.inventory.registered_types():
		var chip := HBoxContainer.new()
		chip.custom_minimum_size.x = 148
		chip.add_theme_constant_override("separation", 9)
		stock_chips[type.id] = chip
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = _resource_icon(type.id)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(icon)
		var numbers := VBoxContainer.new()
		numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		numbers.add_child(ColonyStyle.label(type.display_name + (" / доступно" if type.id == &"food" else ""), 12, ColonyStyle.MUTED))
		var amount: Label = ColonyStyle.label("0", 22)
		numbers.add_child(amount)
		stock_labels[type.id] = amount
		chip.add_child(numbers)
		row.add_child(chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var population_box := VBoxContainer.new()
	population_box.add_child(ColonyStyle.label("МУРАВЬИ", 11, ColonyStyle.MUTED))
	_ants = ColonyStyle.label("0", 22)
	population_box.add_child(_ants)
	row.add_child(population_box)
	var time_box := VBoxContainer.new()
	time_box.custom_minimum_size.x = 80
	time_box.add_child(ColonyStyle.label("ОСТАЛОСЬ", 11, ColonyStyle.MUTED))
	_timer = ColonyStyle.label("08:00", 22, ColonyStyle.ACCENT)
	time_box.add_child(_timer)
	row.add_child(time_box)
	var pause: Button = ColonyStyle.button("Ⅱ")
	pause.custom_minimum_size = Vector2(44, 44)
	pause.tooltip_text = "Пауза · Esc"
	pause.pressed.connect(func(): pause_requested.emit())
	row.add_child(pause)
	controls[&"pause"] = pause
	var settings: Button = ColonyStyle.button("⋮")
	settings.custom_minimum_size = Vector2(44, 44)
	settings.tooltip_text = "Настройки"
	settings.pressed.connect(func(): settings_requested.emit())
	row.add_child(settings)
	controls[&"settings"] = settings
	var objectives := PanelContainer.new()
	objectives.position = Vector2(16, 110)
	objectives.custom_minimum_size = Vector2(240, 0)
	add_child(objectives)
	var goals := VBoxContainer.new()
	goals.add_theme_constant_override("separation", 8)
	objectives.add_child(goals)
	goals.add_child(ColonyStyle.label("ЦЕЛЬ ЭКСПЕДИЦИИ", 11, ColonyStyle.ACCENT))
	goals.add_child(ColonyStyle.label("Соберите по %d" % world.match_controller.target_amount, 20))
	for type in world.match_controller.tracked_types:
		var line := HBoxContainer.new()
		var caption: Label = ColonyStyle.label(type.display_name, 13, ColonyStyle.MUTED)
		caption.custom_minimum_size.x = 90
		line.add_child(caption)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(100, 9)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = world.match_controller.target_amount
		bar.add_theme_stylebox_override("background", ColonyStyle.box(Color("101b18"), Color("33473c")))
		bar.add_theme_stylebox_override("fill", ColonyStyle.box(ColonyStyle.GREEN, ColonyStyle.GREEN, 0))
		line.add_child(bar)
		progress[type.id] = bar
		goals.add_child(line)
	_warning = ColonyStyle.label("", 13, ColonyStyle.DANGER)
	goals.add_child(_warning)
	var bottom := PanelContainer.new()
	add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -54
	bottom.offset_bottom = -12
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 12)
	bottom.add_child(hints)
	var help: Label = ColonyStyle.label("ЛКМ / ПКМ — клетка     ·     Колесо — масштаб     ·     WASD / СКМ — камера", 13, ColonyStyle.MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.add_child(help)
	for key in [&"zoom_out", &"zoom_in"]:
		var button: Button = ColonyStyle.button("−" if key == &"zoom_out" else "+")
		button.custom_minimum_size = Vector2(32, 28)
		button.pressed.connect(func():
			if key == &"zoom_out": zoom_out_requested.emit()
			else: zoom_in_requested.emit())
		hints.add_child(button)
		controls[key] = button
		if key == &"zoom_out":
			_zoom = ColonyStyle.label("×3", 14, ColonyStyle.ACCENT)
			hints.add_child(_zoom)
	_toast = ColonyStyle.label("", 16, ColonyStyle.TEXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", ColonyStyle.box())
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -260
	_toast.offset_right = 260
	_toast.offset_top = -106
	_toast.offset_bottom = -66
	_toast.hide()
	world.inventory.changed.connect(refresh)
	world.population.changed.connect(refresh)
	world.match_controller.time_changed.connect(_on_time_changed)
	refresh()

func _resource_icon(id: StringName) -> Texture2D:
	return world.art.berries if id == &"food" else (world.art.timber if id == &"wood" else world.art.stone)

func refresh() -> void:
	for type in world.inventory.registered_types():
		stock_labels[type.id].text = "%d / %d" % [world.inventory.quantity(type), world.inventory.available(type)] if type.id == &"food" else str(world.inventory.quantity(type))
		stock_chips[type.id].tooltip_text = "Свободно: %d · Зарезервировано: %d" % [world.inventory.available(type), world.inventory.quantity(type) - world.inventory.available(type)]
		if progress.has(type.id):
			progress[type.id].value = world.inventory.quantity(type)
	_ants.text = str(world.population.agents().size())
	var food: ResourceType = world.inventory.type_by_id(&"food")
	_warning.text = "Нужна пища: постройте ягодный куст" if world.inventory.available(food) < 3 else ""

func _on_time_changed(seconds: int) -> void:
	_timer.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_timer.add_theme_color_override("font_color", ColonyStyle.DANGER if seconds <= 30 else ColonyStyle.ACCENT)

func set_zoom(value: int) -> void:
	_zoom.text = "×%d" % value
	controls[&"zoom_in"].disabled = value >= 6
	controls[&"zoom_out"].disabled = value <= 1

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
