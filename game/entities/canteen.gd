extends Building
class_name Canteen

## Inventory and food definition are supplied by the owning world.
var inventory: WorldInventory
var food_type: ResourceType

func configure(stock: WorldInventory, food: ResourceType) -> void:
	inventory = stock
	food_type = food

func has_food() -> bool:
	return inventory != null and inventory.available(food_type) > 0

func try_consume_food(amount: int = 1) -> bool:
	if inventory == null:
		return false
	var cost := ResourceAmount.new()
	cost.type = food_type
	cost.amount = amount
	return inventory.try_spend(cost)
