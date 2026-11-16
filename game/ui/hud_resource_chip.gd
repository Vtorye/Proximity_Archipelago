extends HBoxContainer
## Displays a quantity with the icon authored for its resource type.

func configure(type: ResourceType) -> void:
	$Icon.texture = type.icon
	tooltip_text = type.display_name

func set_amount(amount: int) -> void:
	$Amount.text = str(amount)
