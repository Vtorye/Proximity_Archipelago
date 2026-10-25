class_name UiScaleBinding
extends Node
## Resize native controls and fonts; never shrink a rasterized font through a root transform.
var target: Control
var _controls: Dictionary[Control, Dictionary] = {}
var _styles: Dictionary[StyleBox, Dictionary] = {}
var _constants: Dictionary[String, Dictionary] = {}
var _captured := false

func _ready() -> void:
	AppSettings.changed.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_capture.call_deferred()

func _capture() -> void:
	for item in target.find_children("*", "Control", true, false):
		var control: Control = item
		var values := {"minimum": control.custom_minimum_size, "constants": {}}
		if control.has_theme_font_size_override("font_size"):
			values["font"] = control.get_theme_font_size("font_size")
		for key in ["separation", "h_separation", "margin_left", "margin_right", "margin_top", "margin_bottom", "outline_size"]:
			if control.has_theme_constant_override(key): values["constants"][key] = control.get_theme_constant(key)
		if not (control.get_parent() is Container) and not control.has_meta(&"ui_manual_layout"):
			values["offsets"] = [control.offset_left, control.offset_top, control.offset_right, control.offset_bottom]
		for key in ["panel", "normal", "background", "fill"]:
			if control.has_theme_stylebox_override(key): _capture_style(control.get_theme_stylebox(key))
		_controls[control] = values
		control.set_meta(&"ui_scale_bound", true)
	for type in target.theme.get_type_list():
		for key in target.theme.get_stylebox_list(type): _capture_style(target.theme.get_stylebox(key, type))
		var constants := {}
		for key in target.theme.get_constant_list(type): constants[key] = target.theme.get_constant(key, type)
		_constants[type] = constants
	_captured = true
	_resize()

func _capture_style(style: StyleBox) -> void:
	if _styles.has(style): return
	var values := {}
	for side in ["left", "right", "top", "bottom"]:
		var key: String = "content_margin_" + side
		values[key] = style.get(key)
	_styles[style] = values

func _resize() -> void:
	if not _captured: return
	var factor: float = AppSettings.ui_scale
	target.scale = Vector2.ONE
	target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var body: Dictionary = ColonyStyle.pixel_font(16, factor)
	target.theme.default_font = body["font"]
	target.theme.default_font_size = body["size"]
	target.theme.set_font("font", "TooltipLabel", body["font"])
	target.theme.set_font_size("font_size", "TooltipLabel", body["size"])
	for type in _constants:
		for key in _constants[type]: target.theme.set_constant(key, type, roundi(_constants[type][key] * factor))
	for style in _styles:
		for key in _styles[style]:
			var value: float = _styles[style][key]
			if value >= 0: style.set(key, roundf(value * factor))
	for control in _controls:
		if not is_instance_valid(control): continue
		var values: Dictionary = _controls[control]
		if values.has("font"):
			var font: Dictionary = ColonyStyle.pixel_font(values["font"], factor)
			control.add_theme_font_override("font", font["font"])
			control.add_theme_font_size_override("font_size", font["size"])
		for key in values["constants"]: control.add_theme_constant_override(key, roundi(values["constants"][key] * factor))
		control.custom_minimum_size = (values["minimum"] * factor).round()
		if values.has("offsets"):
			control.offset_left = roundf(values["offsets"][0] * factor)
			control.offset_top = roundf(values["offsets"][1] * factor)
			control.offset_right = roundf(values["offsets"][2] * factor)
			control.offset_bottom = roundf(values["offsets"][3] * factor)
		if control is Button and control.icon != null:
			control.expand_icon = true
			control.add_theme_constant_override("icon_max_width", maxi(8, roundi(16 * factor)))
