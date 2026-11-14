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

static func box(background: Color = PANEL, _border: Color = BORDER, width: int = 1) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = preload("res://game/assets/ui/panel.svg")
	style.texture_margin_left = 3
	style.texture_margin_right = 3
	style.texture_margin_top = 3
	style.texture_margin_bottom = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.modulate_color = Color(1, 1, 1, background.a)
	if width == 0:
		var flat := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		flat.fill(background)
		style.texture = ImageTexture.create_from_image(flat)
		style.modulate_color = Color.WHITE
	return style

static func dialog_box() -> StyleBoxTexture:
	var style: StyleBoxTexture = box()
	style.texture = preload("res://game/assets/ui/dialog.svg")
	return style

static func state_box(name: String) -> StyleBoxTexture:
	var style: StyleBoxTexture = box()
	style.texture = load("res://game/assets/ui/%s.svg" % name) as Texture2D
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

static func _scroll_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.anti_aliasing = false
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

static func apply(control: Control) -> void:
	var theme := Theme.new()
	theme.default_font = SECONDARY_FONT
	theme.default_font_size = maxi(AppSettings.minimum_text_size(), AppSettings.TYPOGRAPHY.body_size)
	theme.set_type_variation("Caption", "Label")
	theme.set_type_variation("Heading", "Label")
	theme.set_type_variation("CompactButton", "Button")
	for type in ["LineEdit", "TextEdit", "Button", "Label", "CheckButton", "OptionButton"]:
		theme.set_font("font", type, theme.default_font)
	theme.set_font("normal_font", "RichTextLabel", theme.default_font)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color.BLACK)
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 1)
	for type in ["Button", "CheckButton", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, state_box("button" if state == "normal" else state))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, ACCENT)
		theme.set_color("font_focus_color", type, ACCENT)
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color("696969"))
		theme.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.35))
	theme.set_stylebox("panel", "PanelContainer", box())
	theme.set_stylebox("panel", "TooltipPanel", box())
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("scroll", "VScrollBar", _scroll_style(Color("1a2020")))
	theme.set_stylebox("scroll_focus", "VScrollBar", _scroll_style(Color("30352f")))
	theme.set_stylebox("grabber", "VScrollBar", _scroll_style(Color("8d8b7f")))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _scroll_style(Color("b9b39c")))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _scroll_style(ACCENT))
	var track := StyleBoxFlat.new()
	track.bg_color = Color("161616")
	track.border_color = Color("666666")
	track.set_border_width_all(1)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	track.anti_aliasing = false
	theme.set_stylebox("slider", "HSlider", track)
	var filled_track := track.duplicate() as StyleBoxFlat
	filled_track.bg_color = ACCENT
	theme.set_stylebox("grabber_area", "HSlider", filled_track)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled_track)
	var knob := Image.create(6, 12, false, Image.FORMAT_RGBA8)
	knob.fill(Color("222222"))
	knob.fill_rect(Rect2i(1, 1, 4, 10), Color("bbbbbb"))
	var knob_texture := ImageTexture.create_from_image(knob)
	theme.set_icon("grabber", "HSlider", knob_texture)
	theme.set_icon("grabber_highlight", "HSlider", knob_texture)
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	control.theme = theme
	if not control.has_node("UiText"):
		var binding := UiTextBinding.new()
		binding.name = "UiText"
		binding.target = control
		control.add_child(binding)

static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
