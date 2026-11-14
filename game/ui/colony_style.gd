class_name ColonyStyle
extends RefCounted

const THEME: Theme = preload("res://game/ui/colony_theme.tres")

static func color(role: StringName) -> Color:
	return THEME.get_color(role, &"UiPalette")

static func apply(control: Control) -> void:
	# The text preference and map contrast are local to this UI root.
	var source: Theme = control.theme if control.theme != null else THEME
	control.theme = source.duplicate(true)
	if not control.has_node("UiText"):
		var binding := UiTextBinding.new()
		binding.name = "UiText"
		binding.target = control
		control.add_child(binding)

static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
