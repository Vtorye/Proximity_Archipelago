class_name WorldInventory
extends Node

signal changed

var _types: Dictionary[StringName, ResourceType] = {}
var _amounts: Dictionary[StringName, int] = {}
var _reserved: Dictionary[StringName, int] = {}
var _tickets: Dictionary[int, StockReservation] = {}
var _next_ticket := 1
var _batch_depth := 0
var _dirty := false


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
	_notify()
	return true


func is_registered(type: ResourceType) -> bool:
	return type != null and _types.has(type.id)


func quantity(type: ResourceType) -> int:
	return _amounts.get(type.id, 0) if type != null else 0


func registered_types() -> Array[ResourceType]:
	return _types.values()


func can_afford(cost: ResourceAmount) -> bool:
	return cost != null and cost.amount >= 0 and is_registered(cost.type) and available(cost.type) >= cost.amount


func try_spend(cost: ResourceAmount, notify: bool = true) -> bool:
	if not can_afford(cost):
		return false
	_amounts[cost.type.id] -= cost.amount
	if notify:
		_notify()
	return true


func add(type: ResourceType, amount: int) -> bool:
	if not is_registered(type) or amount < 0:
		return false
	_amounts[type.id] += amount
	_notify()
	return true

func available(type: ResourceType) -> int:
	return quantity(type) - int(_reserved.get(type.id, 0)) if type != null else 0

func reserve(type: ResourceType, amount: int = 1) -> StockReservation:
	if amount <= 0 or not is_registered(type) or available(type) < amount:
		return null
	var ticket := StockReservation.new()
	ticket.id = _next_ticket
	_next_ticket += 1
	ticket.type = type
	ticket.amount = amount
	_tickets[ticket.id] = ticket
	_reserved[type.id] = int(_reserved.get(type.id, 0)) + amount
	_notify()
	return ticket

func release(ticket: StockReservation) -> bool:
	if ticket == null or not ticket.active or _tickets.get(ticket.id) != ticket:
		return false
	_reserved[ticket.type.id] -= ticket.amount
	_tickets.erase(ticket.id)
	ticket.active = false
	_notify()
	return true

func consume(ticket: StockReservation) -> bool:
	if ticket == null or not ticket.active or _tickets.get(ticket.id) != ticket:
		return false
	begin_update()
	_amounts[ticket.type.id] -= ticket.amount
	release(ticket)
	end_update()
	return true

func begin_update() -> void:
	_batch_depth += 1

func end_update() -> void:
	assert(_batch_depth > 0)
	_batch_depth -= 1
	if _batch_depth == 0 and _dirty:
		_dirty = false
		changed.emit()

func _notify() -> void:
	if _batch_depth > 0:
		_dirty = true
	else:
		changed.emit()
