class_name TaskVariant
extends Resource
## One authored way to complete an order. The ID is stable within its task.

@export var id: StringName
@export var label: String
@export var building: BuildOption
## Negative uses the task's default time reward.
@export var reward_seconds := -1.0
## Empty uses the task's default resource reward.
@export var rewards: Array[ResourceAmount] = []
