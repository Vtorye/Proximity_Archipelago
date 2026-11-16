class_name BuildCategory
extends Resource
## A named palette section. Only unlocked options from this list are shown.
@export var title: String
@export var options: Array[BuildOption] = []
