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
