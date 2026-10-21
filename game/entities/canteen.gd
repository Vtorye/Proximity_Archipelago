extends Building
class_name Canteen

# I don't really understand... am I *supposed to* hardcode it?
# or should I do something like
## @export var meal_cost: ResourceAmount
# but where would I assighn it from?
# or is it just temporarily that canteen doesn't have a node?
# or should I do
## preload("uid://bc4vd8o7qyldd") // food.tres ?? 

#@export var resource_type : StringName = &"food"
const FOOD = preload("uid://bc4vd8o7qyldd")


func _enter_tree() -> void:
	add_to_group("canteens")


func has_food() -> bool:
	return inventory.quantity(FOOD) > 0
	#return inventory.quantity(meal_cost.type) > 0


func try_consume_food(amount: int = 1) -> bool:
	# this is ugly. should we make try_spend() that takes them separatly?
	var res_am : ResourceAmount = ResourceAmount.new()
	res_am.type = FOOD
	res_am.amount = amount
	
	return inventory.try_spend(res_am)
