class_name WorldInventory
extends Node

signal changed

var _types: Dictionary[StringName, ResourceType] = {}
var _amounts: Dictionary[StringName, int] = {}


## Reject the entire configuration on invalid entries; never mutate definitions.
func configure(entries: Array[ResourceAmount]) -> bool:
	var types: Dictionary[StringName, ResourceType] = {}
	var amounts: Dictionary[StringName, int] = {}
	for entry in entries:
		if entry == null or entry.type == null or entry.type.id == &"" or entry.amount < 0:
			push_error("Invalid world resource registration")
			return false
		if types.has(entry.type.id):
			push_error("Duplicate world resource ID: %s" % entry.type.id)
			return false
		types[entry.type.id] = entry.type
		amounts[entry.type.id] = entry.amount
	_types = types
	_amounts = amounts
	changed.emit()
	return true


func is_registered(type: ResourceType) -> bool:
	return type != null and _types.has(type.id)


func quantity(type: ResourceType) -> int:
	return _amounts.get(type.id, 0) if type != null else 0


func registered_types() -> Array[ResourceType]:
	return _types.values()


func can_afford(cost: ResourceAmount) -> bool:
	return cost != null and cost.amount >= 0 and is_registered(cost.type) and quantity(cost.type) >= cost.amount


func try_spend(cost: ResourceAmount, notify: bool = true) -> bool:
	if not can_afford(cost):
		return false
	_amounts[cost.type.id] -= cost.amount
	if notify:
		changed.emit()
	return true


func add(type: ResourceType, amount: int) -> bool:
	if not is_registered(type) or amount < 0:
		return false
	_amounts[type.id] += amount
	changed.emit()
	return true
