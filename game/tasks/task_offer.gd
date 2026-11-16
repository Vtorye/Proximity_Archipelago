class_name TaskOffer
extends VBoxContainer
## A construction card with the reward for its task variant below it.

signal order_requested(task_id: StringName, variant_id: StringName)
signal info_requested(option: BuildOption)

@export var selected_frame: StyleBox

var order: TaskBuildOrder
var _selected := false
@onready var placement: ConstructionCard = %Placement
@onready var reward: RichTextLabel = %Reward

func _ready() -> void:
	placement.pressed.connect(_request_order)
	placement.info_requested.connect(info_requested.emit)

func configure(offer: TaskBuildOrder, art: ArtCatalog) -> void:
	order = offer
	var variant := order.variant
	var title := variant.label if not variant.label.is_empty() else variant.building.display_name
	var icon: Texture2D
	if variant.building is SceneBuildOption:
		var appearance_variants := (variant.building as SceneBuildOption).appearance_variants
		if appearance_variants != null and not appearance_variants.textures.is_empty():
			icon = appearance_variants.textures.pick_random()
	placement.configure(variant.building, art, icon)
	placement.tooltip_text = title
	BuildCostText.show_reward(reward, order.resources(), order.time_reward())

func refresh_price(controller: BuildController) -> void:
	placement.set_price(controller.price(order.variant.building))

func set_available(available: bool) -> void:
	placement.disabled = not available

func set_selected(selected: bool) -> void:
	_selected = selected
	placement.set_pressed_no_signal(selected)
	if selected and selected_frame != null:
		placement.add_theme_stylebox_override(&"disabled", selected_frame)
	else:
		placement.remove_theme_stylebox_override(&"disabled")

func _request_order() -> void:
	placement.set_pressed_no_signal(_selected)
	AppSettings.play_click()
	order_requested.emit(order.task.id, order.variant.id)
