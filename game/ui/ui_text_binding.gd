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
	_apply_theme(target.theme, typography, minimum, tooltip_size)
	_apply_children(target, typography, minimum, tooltip_size)

func _apply_children(root: Node, typography: UiTypography, minimum: int, tooltip_size: int) -> void:
	for child in root.get_children():
		if child is Control and child.theme != null:
			_apply_theme(child.theme, typography, minimum, tooltip_size)
		_apply_children(child, typography, minimum, tooltip_size)

func _apply_theme(theme: Theme, typography: UiTypography, minimum: int, tooltip_size: int) -> void:
	theme.set_font_size("font_size", "TooltipLabel", tooltip_size)
	var body: int = maxi(minimum, typography.body_size)
	theme.default_font_size = body
	for type in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "TextEdit"]:
		theme.set_font_size("font_size", type, body)
	theme.set_font_size("normal_font_size", "RichTextLabel", body)
	theme.set_font_size("font_size", "Caption", maxi(minimum, typography.caption_size))
	theme.set_font_size("font_size", "Heading", maxi(minimum, typography.heading_size))
	theme.set_font_size("font_size", "CompactButton", maxi(minimum, typography.compact_button_size))
