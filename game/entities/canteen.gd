extends Node2D
class_name Canteen

@export_range(0, 100000) var food: int = 10


func _enter_tree() -> void:
	add_to_group("canteens")


func has_food() -> bool:
	return food > 0


func consume_food(amount: int = 1) -> int:
	var consumed := mini(maxi(amount, 0), food)
	food -= consumed
	return consumed
