class_name ColonyStyle
extends RefCounted
## Shared visual tokens; menus compose controls without depending on scene nesting.
const BACKGROUND := Color("111d1d")
const PANEL := Color("1b2b29")
const RAISED := Color("253936")
const BORDER := Color("40534b")
const TEXT := Color("eee8d5")
const MUTED := Color("9fad9d")
const ACCENT := Color("e4b86c")
const DANGER := Color("e5927d")
const GREEN := Color("a1c58c")

static func box(background: Color = PANEL, border: Color = BORDER, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func apply(control: Control) -> void:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", TEXT)
	for type in ["Button", "CheckButton", "OptionButton"]:
		theme.set_stylebox("normal", type, box())
		theme.set_stylebox("hover", type, box(RAISED, ACCENT))
		theme.set_stylebox("pressed", type, box(Color("394934"), ACCENT))
		theme.set_stylebox("disabled", type, box(Color("172321"), Color("2b3c35")))
		theme.set_stylebox("focus", type, box(Color(0, 0, 0, 0), ACCENT, 2))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_disabled_color", type, Color("718074"))
	theme.set_stylebox("panel", "PanelContainer", box())
	theme.set_stylebox("panel", "TooltipPanel", box(BACKGROUND, ACCENT))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 15)
	control.theme = theme

static func label(text: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func button(text: String, primary: bool = false, feedback: bool = true) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 44
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		result.add_theme_stylebox_override("normal", box(Color("665234"), ACCENT))
	if feedback:
		result.pressed.connect(func(): AppSettings.play_click())
	return result

static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func margin(parent: Node, pixels: int = 20) -> MarginContainer:
	var result := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		result.add_theme_constant_override("margin_" + side, pixels)
	parent.add_child(result)
	return result

static func modal(root: Control, width: float = 560.0) -> VBoxContainer:
	apply(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.06, 0.8)
	root.add_child(shade)
	fill(shade)
	var center := CenterContainer.new()
	root.add_child(center)
	fill(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin(panel, 16).add_child(content)
	return content
