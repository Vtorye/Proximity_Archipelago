class_name TaskSpec
extends Resource
@export var id: StringName
@export var title: String
## Number of structures needed to fulfil this request.
@export_range(1, 100, 1) var build_count := 1
@export var reward_seconds := 20.0
@export var rewards: Array[ResourceAmount] = []
@export var unlocks: Array[BuildOption] = []
@export var variants: Array[TaskVariant] = []

func variant_by_id(variant_id: StringName) -> TaskVariant:
	for variant in variants:
		if variant != null and variant.id == variant_id:
			return variant
	return null
