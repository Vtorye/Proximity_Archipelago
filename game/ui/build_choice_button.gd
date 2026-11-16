class_name BuildChoiceButton
extends Button
## A shared pixel button with a separate, wrapping multi-resource price line.
var option: BuildOption
var controller: BuildController
var art: ArtCatalog
@onready var cost_label: Label = %Cost
var card_width := 176
var compact := false
var pricing_cell := Vector2i(2147483647, 2147483647)
@onready var _body: MarginContainer = %Body
var _minimum_height := 44.0

func _ready() -> void:
	_minimum_height = 28.0 if compact else 44.0
	custom_minimum_size = Vector2(card_width, _minimum_height)
	pressed.connect(AppSettings.play_click)
	for side in ["left", "right"]:
		_body.add_theme_constant_override("margin_" + side, 4 if compact else 6)
	var icon: TextureRect = %Icon
	icon.texture = art.build_icon(option)
	icon.custom_minimum_size = Vector2.ONE * (16 if compact else 24)
	if option.id == &"house":
		icon.modulate = House.BARRACKS_TINT
	%Caption.text = option.display_name
	cost_label.text = BuildCostText.format(controller.price(option, pricing_cell) if controller != null else option.costs)
	cost_label.set("theme_type_variation", &"Caption")
	minimum_size_changed.connect(_fit_content)
	_body.minimum_size_changed.connect(_fit_content)
	if controller != null and controller.prices != null: controller.prices.changed.connect(_refresh_price)
	_fit_content()

func _refresh_price() -> void:
	cost_label.text = BuildCostText.format(controller.price(option, pricing_cell))

func set_pricing_cell(cell: Vector2i) -> void:
	if pricing_cell == cell: return
	pricing_cell = cell
	if cost_label != null: _refresh_price()
	tooltip_text = "%s: %s" % [tr(option.display_name), BuildCostText.format(controller.price(option, pricing_cell))]

func _process(_delta: float) -> void:
	_body.modulate.a = 0.35 if disabled else 1.0

func _fit_content() -> void:
	if get_child_count() > 0:
		custom_minimum_size.y = maxf(_minimum_height, _body.get_combined_minimum_size().y)
