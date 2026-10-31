class_name TaskStage
extends Resource
@export var tasks: Array[TaskSpec] = []
@export_enum("Road", "Discount", "Speed") var upgrade := 0
@export var upgrade_factor := 0.9
