class_name TaskBuildOrder
extends RefCounted
## Identifies the exact task and variant behind a placement or construction site.
var task: TaskSpec
var variant: TaskVariant

func _init(spec: TaskSpec, choice: TaskVariant) -> void:
	task = spec
	variant = choice

func time_reward() -> float:
	return variant.reward_seconds if variant.reward_seconds >= 0.0 else task.reward_seconds

func resources() -> Array[ResourceAmount]:
	return variant.rewards if not variant.rewards.is_empty() else task.rewards
