class_name TaskSpec
extends Resource
@export var id: StringName
@export var title: String
@export var reward_seconds := 20.0
@export var rewards: Array[ResourceAmount] = []
@export var unlocks: Array[BuildOption] = []
@export_group("Royal order")
@export var building: BuildOption
@export var diversion: BuildOption
@export var building_label: String
@export var diversion_label: String
@export_group("Variant rewards")
@export var building_reward_seconds := -1.0
@export var building_rewards: Array[ResourceAmount] = []
@export var diversion_reward_seconds := -1.0
@export var diversion_rewards: Array[ResourceAmount] = []

func time_reward_for(is_diversion: bool) -> float:
	var seconds := diversion_reward_seconds if is_diversion else building_reward_seconds
	return seconds if seconds >= 0.0 else reward_seconds

func resources_for(is_diversion: bool) -> Array[ResourceAmount]:
	var variant_rewards := diversion_rewards if is_diversion else building_rewards
	return variant_rewards if not variant_rewards.is_empty() else rewards
