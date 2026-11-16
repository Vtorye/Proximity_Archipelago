extends Button
## A task offer uses the same resource textures in its reward tooltip as the HUD.

const REWARD_TOOLTIP: PackedScene = preload("res://game/tasks/task_reward_tooltip.tscn")
var _rewards: Array[ResourceAmount] = []

func set_reward_tooltip(label: String, time: String, rewards: Array[ResourceAmount]) -> void:
	tooltip_text = "%s\n%s" % [label, time]
	_rewards = rewards

func _make_custom_tooltip(for_text: String) -> Control:
	var tooltip: RichTextLabel = REWARD_TOOLTIP.instantiate()
	tooltip.theme = theme if theme != null else ColonyStyle.theme_for_text_size(AppSettings.text_size)
	BuildCostText.show_price(tooltip, _rewards, for_text + "\n%s")
	return tooltip
