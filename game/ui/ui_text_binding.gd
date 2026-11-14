class_name UiTextBinding
extends Node
## The player preference raises the authored size of each text role.
var target: Control

func _ready() -> void:
	AppSettings.changed.connect(_apply_size)
	_apply_size()

func _apply_size() -> void:
	var typography: UiTypography = AppSettings.TYPOGRAPHY
	var minimum: int = AppSettings.minimum_text_size()
	var tooltip_size: int = maxi(minimum, typography.caption_size)
	ColonyStyle.THEME.set_font_size("font_size", "TooltipLabel", tooltip_size)
	target.theme.set_font_size("font_size", "TooltipLabel", tooltip_size)
	var body: int = maxi(minimum, typography.body_size)
	target.theme.default_font_size = body
	for type in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "TextEdit"]:
		target.theme.set_font_size("font_size", type, body)
	target.theme.set_font_size("normal_font_size", "RichTextLabel", body)
	target.theme.set_font_size("font_size", "Caption", maxi(minimum, typography.caption_size))
	target.theme.set_font_size("font_size", "Heading", maxi(minimum, typography.heading_size))
	target.theme.set_font_size("font_size", "CompactButton", maxi(minimum, typography.compact_button_size))
