class_name BuildChoiceButton
extends Button
## A shared pixel button with a separate, wrapping multi-resource price line.
var option: BuildOption
var art: ArtCatalog
var cost_label: Label
var card_width := 176
var compact := false
var _body: MarginContainer
var _minimum_height := 44.0

func _ready() -> void:
	_minimum_height = 28.0 if compact else 44.0
	custom_minimum_size = Vector2(card_width, _minimum_height)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(AppSettings.play_click)
	var margin := MarginContainer.new()
	_body = margin
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 4 if compact else 6)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)
	var icon_view := TextureRect.new()
	icon_view.texture = option.icon if option.icon != null else default_icon(option, art)
	icon_view.custom_minimum_size = Vector2.ONE * (16 if compact else 24)
	icon_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_view)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 0)
	row.add_child(lines)
	var caption: Label = ColonyStyle.label(option.display_name, 6 if compact else 8)
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lines.add_child(caption)
	cost_label = ColonyStyle.label(BuildCostText.format(option.costs), 4 if compact else 6, ColonyStyle.MUTED)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(cost_label)
	minimum_size_changed.connect(_fit_content)
	margin.minimum_size_changed.connect(_fit_content)
	_fit_content()

func _process(_delta: float) -> void:
	_body.modulate.a = 0.35 if disabled else 1.0

func _fit_content() -> void:
	if get_child_count() > 0:
		var factor: float = AppSettings.ui_scale if has_meta(&"ui_scale_bound") else 1.0
		custom_minimum_size.y = maxf(roundf(_minimum_height * factor), get_child(0).get_combined_minimum_size().y)

static func default_icon(definition: BuildOption, catalog: ArtCatalog) -> Texture2D:
	match definition.id:
		&"road": return catalog.road
		&"ground": return catalog.soil
		&"house": return catalog.nest
		&"apple_tree": return catalog.berries
	return catalog.stone
