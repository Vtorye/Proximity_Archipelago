class_name ConstructionCard
extends Button
signal info_requested(option: BuildOption)

@onready var _image: TextureRect = %Image
@onready var _cost: RichTextLabel = %Cost
@onready var _title: Label = %OfferTitle
@onready var _reward: RichTextLabel = %Reward
@onready var _info: Button = %Info
@onready var _margin: MarginContainer = %Margin
@onready var _authored_minimum: Vector2 = custom_minimum_size
var option: BuildOption
var _offer: TaskBuildOrder

func _ready() -> void:
	_margin.minimum_size_changed.connect(_fit_content)
	_fit_content()
	_info.pressed.connect(func():
		if option != null:
			AppSettings.play_click()
			info_requested.emit(option))

func configure(option: BuildOption, art: ArtCatalog) -> void:
	self.option = option
	_image.texture = art.build_icon(option)
	tooltip_text = option.display_name
	set_price(option.costs)

func set_price(price: Array[ResourceAmount]) -> void:
	BuildCostText.show_price(_cost, price, "− %s" if _offer != null else "%s", "—" if _offer != null else "")

func show_offer(order: TaskBuildOrder, price: Array[ResourceAmount]) -> void:
	_offer = order
	_title.text = order.variant.label if not order.variant.label.is_empty() else option.display_name
	_title.show()
	_reward.show()
	BuildCostText.show_reward(_reward, order.resources(), order.time_reward())
	set_price(price)

func _fit_content() -> void:
	# The button does not include its child controls in its own minimum size.
	custom_minimum_size = _authored_minimum.max(_margin.get_combined_minimum_size())
