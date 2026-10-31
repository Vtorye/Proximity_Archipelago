class_name TaskSpec
extends Resource
@export var id: StringName
@export var title: String
@export var costs: Array[ResourceAmount] = []
@export var cancellation_costs: Array[ResourceAmount] = []
@export var reward_seconds := 20.0
@export var rewards: Array[ResourceAmount] = []
