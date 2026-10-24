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


var _world: World


## Warehouse of the World this canteen belongs to. Null until that World has set up its inventory.
func _get_inventory() -> WorldInventory:
	if not is_instance_valid(_world):
		_world = _find_world()
	if _world == null:
		return null
	return _world.inventory


func _find_world() -> World:
	var node := get_parent()
	while node != null:
		if node is World:
			return node as World
		node = node.get_parent()
	return null


func has_food() -> bool:
	var stock := _get_inventory()
	return stock != null and stock.quantity(FOOD) > 0
	#return inventory.quantity(meal_cost.type) > 0


func try_consume_food(amount: int = 1) -> bool:
	var stock := _get_inventory()
	if stock == null:
		return false
	# this is ugly. should we make try_spend() that takes them separatly?
	var res_am : ResourceAmount = ResourceAmount.new()
	res_am.type = FOOD
	res_am.amount = amount
	
	return stock.try_spend(res_am)
