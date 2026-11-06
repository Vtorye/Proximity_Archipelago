class_name WorldInventory
extends Node

signal changed

var _types: Dictionary[StringName, ResourceType] = {}
var _amounts: Dictionary[StringName, int] = {}
var _main_stock: Dictionary[StringName, int] = {}
var _depots: Dictionary[House, Dictionary] = {}
var _transit: Dictionary[StringName, int] = {}
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
	for ticket in _tickets.values():
		ticket.active = false
	_tickets.clear()
	_reserved.clear()
	_types = types
	_amounts = amounts
	_main_stock = amounts.duplicate()
	_transit.clear()
	for stock in _depots.values():
		stock.clear()
	_notify()
	return true


func is_registered(type: ResourceType) -> bool:
	return type != null and _types.has(type.id)


func quantity(type: ResourceType) -> int:
	return _amounts.get(type.id, 0) if type != null else 0


func registered_types() -> Array[ResourceType]:
	return _types.values()


func can_afford(cost: ResourceAmount) -> bool:
	return can_afford_all([cost])


func try_spend(cost: ResourceAmount) -> bool:
	return try_spend_all([cost])


## Duplicate resource IDs share one budget, including outstanding food reservations.
func can_afford_all(costs: Array[ResourceAmount], main_only: bool = false) -> bool:
	var totals: Dictionary[StringName, int] = {}
	for cost in costs:
		if cost == null or cost.amount < 0 or not is_registered(cost.type):
			return false
		totals[cost.type.id] = totals.get(cost.type.id, 0) + cost.amount
		var limit: int = available(cost.type)
		if main_only:
			limit = mini(limit, main_quantity(cost.type))
		if totals[cost.type.id] > limit:
			return false
	return true


## Validate every component before spending; observers see only the complete purchase.
func try_spend_all(costs: Array[ResourceAmount], main_only: bool = false) -> bool:
	if not can_afford_all(costs, main_only):
		return false
	for cost in costs:
		_withdraw(cost.type.id, cost.amount)
	if not costs.is_empty():
		_notify()
	return true


func add(type: ResourceType, amount: int) -> bool:
	if not is_registered(type) or amount < 0:
		return false
	_amounts[type.id] += amount
	_main_stock[type.id] += amount
	_notify()
	return true

func available(type: ResourceType) -> int:
	return quantity(type) - int(_reserved.get(type.id, 0)) - int(_transit.get(type.id, 0)) if type != null else 0

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
	_withdraw(ticket.type.id, ticket.amount)
	release(ticket)
	end_update()
	return true

func main_quantity(type: ResourceType) -> int:
	return _main_stock.get(type.id, 0) if type != null else 0

func register_depot(house: House) -> void:
	_depots[house] = {}

func unregister_depot(house: House) -> void:
	var stock: Dictionary = _depots.get(house, {})
	for id: StringName in stock:
		_main_stock[id] += stock[id]
	_depots.erase(house)
	if not stock.is_empty():
		_notify()

func depot_quantity(house: House, type: ResourceType) -> int:
	return _depots.get(house, {}).get(type.id, 0) if type != null else 0

func depot_fill(house: House) -> int:
	var count := 0
	for amount: int in _depots.get(house, {}).values():
		count += amount
	return count

func can_deposit(house: House, count: int) -> bool:
	return count >= 0 and (house == null or (_depots.has(house) and count <= house.storage_capacity - depot_fill(house)))

func deposit(house: House, cargo: Array[ResourceAmount]) -> bool:
	for item in cargo:
		if item == null or item.amount <= 0 or not is_registered(item.type):
			return false
	if not can_deposit(house, cargo_size(cargo)):
		return false
	var stock: Dictionary = _main_stock if house == null else _depots[house]
	for item in cargo:
		var id: StringName = item.type.id
		stock[id] = int(stock.get(id, 0)) + item.amount
		_amounts[id] += item.amount
	if not cargo.is_empty():
		_notify()
	return true

## Move unreserved stock out of a depot. It stays in colony totals while in transit.
func dispatch(house: House, limit: int) -> Array[ResourceAmount]:
	var cargo: Array[ResourceAmount] = []
	var stock: Dictionary = _depots.get(house, {})
	for id: StringName in stock:
		var type: ResourceType = _types[id]
		var amount: int = mini(limit, mini(stock[id], available(type)))
		if amount <= 0:
			continue
		var item := ResourceAmount.new()
		item.type = type
		item.amount = amount
		cargo.append(item)
		stock[id] -= amount
		_transit[id] = int(_transit.get(id, 0)) + amount
		limit -= amount
		if limit <= 0:
			break
	if not cargo.is_empty():
		_notify()
	return cargo

func close_shipment(cargo: Array[ResourceAmount], delivered: bool) -> void:
	for item in cargo:
		var id: StringName = item.type.id
		_transit[id] -= item.amount
		if delivered:
			_main_stock[id] += item.amount
		else:
			_amounts[id] -= item.amount
	if not cargo.is_empty():
		_notify()

static func cargo_size(cargo: Array[ResourceAmount]) -> int:
	var count := 0
	for item in cargo:
		count += item.amount
	return count

func _withdraw(id: StringName, count: int) -> void:
	_amounts[id] -= count
	var from_main: int = mini(_main_stock[id], count)
	_main_stock[id] -= from_main
	var remaining: int = count - from_main
	if remaining == 0:
		return
	for stock in _depots.values():
		var taken: int = mini(stock.get(id, 0), remaining)
		if taken > 0:
			stock[id] -= taken
			remaining -= taken
		if remaining == 0:
			return

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

func type_by_id(id: StringName) -> ResourceType:
	return _types.get(id)
