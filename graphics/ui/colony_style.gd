class_name ColonyStyle
extends RefCounted

const THEME: Theme = preload("res://graphics/ui/colony_theme.tres")
const TYPOGRAPHY: UiTypography = preload("res://graphics/ui/ui_typography.tres")
static var _text_themes: Dictionary[int, Theme] = {}

static func color(role: StringName) -> Color:
	return THEME.get_color(role, &"UiPalette")

static func theme_for_text_size(index: int) -> Theme:
	if _text_themes.has(index):
		return _text_themes[index]
	var typography: UiTypography = TYPOGRAPHY
	var minimum := typography.minimum_sizes[index]
	# Configure the variant before any Control observes it. Fonts and styles are shared.
	var theme := THEME.duplicate() as Theme
	var body := maxi(minimum, typography.body_size)
	theme.default_font_size = body
	for type in [&"Label", &"Button", &"CheckButton", &"OptionButton", &"PopupMenu", &"LineEdit", &"TextEdit"]:
		theme.set_font_size(&"font_size", type, body)
	theme.set_font_size(&"normal_font_size", &"RichTextLabel", body)
	var caption := maxi(minimum, typography.caption_size)
	theme.set_font_size(&"font_size", &"Caption", caption)
	theme.set_font_size(&"normal_font_size", &"PriceCaption", caption)
	theme.set_font_size(&"font_size", &"TooltipLabel", caption)
	theme.set_font_size(&"font_size", &"Heading", maxi(minimum, typography.heading_size))
	theme.set_font_size(&"font_size", &"CompactButton", maxi(minimum, typography.compact_button_size))
	var details_size := typography.details_body_size + index * typography.details_size_step
	theme.set_font_size(&"font_size", &"DetailsText", details_size)
	theme.set_font_size(&"normal_font_size", &"DetailsRichText", details_size)
	theme.set_font_size(&"font_size", &"DetailsHeading", typography.details_heading_size + index * typography.details_size_step)
	_text_themes[index] = theme
	return theme

static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
