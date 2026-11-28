class_name WorkRecipe
extends Resource
## Inputs are consumed atomically from free stock. Reserved meals are never ingredients.
@export var inputs: Array[ResourceAmount] = []
@export var outputs: Array[ResourceAmount] = []

func valid() -> bool:
	if outputs.is_empty(): return false
	for entry in inputs + outputs:
		if entry == null or entry.type == null or entry.amount <= 0: return false
	return true
