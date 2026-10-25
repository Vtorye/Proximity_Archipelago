class_name ColonyStyle
extends RefCounted
## One low-resolution, nine-slice theme shared by every overlay and HUD control.
const BACKGROUND := Color("080808")
const PANEL := Color("292929")
const RAISED := Color("454545")
const BORDER := Color("858585")
const TEXT := Color("eee8d5")
const MUTED := Color("aaa69c")
const ACCENT := Color("dfc68b")
const DANGER := Color("d98a79")
const GREEN := Color("b9c79b")
const FONT := preload("res://game/assets/fonts/BoldPixels.ttf")
const SECONDARY_FONT := preload("res://game/assets/fonts/Pixuf.ttf")

static func box(background: Color = PANEL, border: Color = BORDER, width: int = 1) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = preload("res://game/assets/ui/panel.svg")
	style.texture_margin_left = 3
	style.texture_margin_right = 3
	style.texture_margin_top = 3
	style.texture_margin_bottom = 3
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.modulate_color = Color(1, 1, 1, background.a)
	if width == 0:
		var flat := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		flat.fill(background)
		style.texture = ImageTexture.create_from_image(flat)
		style.modulate_color = Color.WHITE
	return style

static func state_box(name: String) -> StyleBoxTexture:
	var style: StyleBoxTexture = box()
	style.texture = load("res://game/assets/ui/%s.svg" % name) as Texture2D
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

static func apply(control: Control) -> void:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 8
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color.BLACK)
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 1)
	for type in ["Button", "CheckButton", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, state_box("button" if state == "normal" else state))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, ACCENT)
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color("696969"))
		theme.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.35))
	theme.set_stylebox("panel", "PanelContainer", box())
	theme.set_stylebox("panel", "TooltipPanel", box())
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 8)
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	control.theme = theme

static func label(text: String, font_size: int = 8, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = text
	# Existing callers can migrate independently from the old high-resolution layout.
	var pixels: int = font_size if font_size <= 12 else (12 if font_size >= 28 else 8)
	result.add_theme_font_size_override("font_size", pixels)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func button(text: String, primary: bool = false, feedback: bool = true) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 14
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		result.add_theme_color_override("font_color", ACCENT)
	if feedback:
		result.pressed.connect(func(): AppSettings.play_click())
	return result

static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func margin(parent: Node, pixels: int = 4) -> MarginContainer:
	var result := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		result.add_theme_constant_override("margin_" + side, pixels)
	parent.add_child(result)
	return result

static func modal(root: Control, width: float = 248.0) -> VBoxContainer:
	apply(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	root.add_child(shade)
	fill(shade)
	var center := CenterContainer.new()
	root.add_child(center)
	fill(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(width, 304)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	margin(panel, 3).add_child(content)
	return content
