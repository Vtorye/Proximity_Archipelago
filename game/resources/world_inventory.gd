class_name WorldInventory
extends Node

signal changed

## Physical goods held by the main nest. Royal is a crown currency, not carried by ants.
const MAIN_CAPACITY := 1000
const CURRENCY_ID := &"royal"

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
func can_afford_all(costs: Array[ResourceAmount], main_only: bool = false, use_reserved_food := false) -> bool:
	var totals: Dictionary[StringName, int] = {}
	for cost in costs:
		if cost == null or cost.amount < 0 or not is_registered(cost.type):
			return false
		totals[cost.type.id] = totals.get(cost.type.id, 0) + cost.amount
		var limit: int = _physical_stock(cost.type) if use_reserved_food and cost.type.id == &"food" else available(cost.type)
		if main_only:
			limit = mini(limit, main_quantity(cost.type))
		if totals[cost.type.id] > limit:
			return false
	return true


## Validate every component before spending; observers see only the complete purchase.
func try_spend_all(costs: Array[ResourceAmount], main_only: bool = false, use_reserved_food := false) -> bool:
	if not can_afford_all(costs, main_only, use_reserved_food):
		return false
	for cost in costs:
		_withdraw(cost.type.id, cost.amount, main_only)
	if not costs.is_empty():
		_notify()
	return true


## Preview crates without debiting any stock. Orders share a temporary ledger.
func allocate_build_materials(costs: Array[ResourceAmount], primary: House, sources: Array[House], planned: Dictionary) -> Variant:
	var crates: Dictionary = {}
	for cost in costs:
		var remaining: int = cost.amount
		for source in sources:
			var stock: Dictionary = _main_stock if source == primary else _depots[source]
			if not planned.has(source):
				planned[source] = {}
			var used: int = planned[source].get(cost.type.id, 0)
			var taken: int = mini(remaining, stock.get(cost.type.id, 0) - used)
			if taken <= 0:
				continue
			planned[source][cost.type.id] = used + taken
			var item := ResourceAmount.new()
			item.type = cost.type
			item.amount = taken
			if not crates.has(source):
				crates[source] = []
			crates[source].append(item)
			remaining -= taken
			if remaining == 0:
				break
		if remaining > 0:
			return null
	return crates

## Commit the allocation once all orders and their combined budget have passed preflight.
func debit_build_materials(crates: Dictionary, primary: House) -> void:
	for source: House in crates:
		var stock: Dictionary = _main_stock if source == primary else _depots[source]
		for item: ResourceAmount in crates[source]:
			stock[item.type.id] -= item.amount
			_amounts[item.type.id] -= item.amount
	if not crates.is_empty():
		_notify()


func add(type: ResourceType, amount: int) -> bool:
	if not is_registered(type) or amount < 0:
		return false
	_amounts[type.id] += amount
	_main_stock[type.id] += amount
	_notify()
	return true

func available(type: ResourceType) -> int:
	return _physical_stock(type) - int(_reserved.get(type.id, 0)) if type != null else 0

func _physical_stock(type: ResourceType) -> int:
	return quantity(type) - int(_transit.get(type.id, 0))

func reserve(type: ResourceType, amount: int = 1, restoring := false) -> StockReservation:
	if amount <= 0 or not is_registered(type) or (not restoring and available(type) < amount):
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
	if _physical_stock(ticket.type) < ticket.amount:
		release(ticket)
		return false
	begin_update()
	_withdraw(ticket.type.id, ticket.amount)
	release(ticket)
	end_update()
	return true

func main_quantity(type: ResourceType) -> int:
	if type == null:
		return 0
	var amount: int = _main_stock.get(type.id, 0)
	for house in _depots:
		if house.is_main_nest:
			amount += depot_quantity(house, type)
	return amount

## The first base owns starting stock; other nests have separate physical inventories.
func nest_quantity(house: House, primary: House, type: ResourceType) -> int:
	return _main_stock.get(type.id, 0) if house == primary and type != null else depot_quantity(house, type)

## Enemy destruction loses physical stock; it cannot be promoted or refunded to another base.
func destroy_nest(house: House, primary: House) -> void:
	begin_update()
	var stock: Dictionary = _main_stock if house == primary else _depots.get(house, {})
	for id: StringName in stock:
		_amounts[id] -= stock[id]
		if house == primary: stock[id] = 0
	if house != primary: stock.clear()
	# Meals reserved against destroyed supplies must become unavailable, never negative stock.
	for ticket: StockReservation in _tickets.values().duplicate():
		if available(ticket.type) < 0: release(ticket)
	_notify()
	end_update()

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

## Physical goods held by one base (null is the first base). Royal is currency, not cargo.
func storage_load(house: House) -> int:
	var stock: Dictionary = _main_stock if house == null else _depots.get(house, {})
	var total := 0
	for id: StringName in stock:
		if id != CURRENCY_ID:
			total += stock[id]
	return total

## True when at least one base can take this many goods.
func has_base_room(count: int) -> bool:
	if can_deposit(null, count):
		return true
	for house: House in _depots:
		if house.is_main_nest and can_deposit(house, count):
			return true
	return false

## Each base holds up to MAIN_CAPACITY; barracks use their own storage_capacity.
func can_deposit(house: House, count: int) -> bool:
	if count < 0:
		return false
	if house == null:
		return storage_load(null) + count <= MAIN_CAPACITY
	if not _depots.has(house):
		return false
	if house.is_main_nest:
		return storage_load(house) + count <= MAIN_CAPACITY
	return count <= house.storage_capacity - depot_fill(house)

## force skips capacity limits for refunds so paid materials are never lost.
func deposit(house: House, cargo: Array[ResourceAmount], force := false) -> bool:
	for item in cargo:
		if item == null or item.amount <= 0 or not is_registered(item.type):
			return false
	var fits: bool = (force and (house == null or _depots.has(house))) or can_deposit(house, cargo_size(cargo))
	if not fits:
		return false
	var stock: Dictionary = _main_stock if house == null else _depots[house]
	for item in cargo:
		var id: StringName = item.type.id
		stock[id] = int(stock.get(id, 0)) + item.amount
		_amounts[id] += item.amount
	if not cargo.is_empty():
		_notify()
	return true

func has_dispatchable_stock(house: House) -> bool:
	var stock: Dictionary = _depots.get(house, {})
	for id: StringName in stock:
		if stock[id] > 0 and available(_types[id]) > 0:
			return true
	return false

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

func close_shipment(cargo: Array[ResourceAmount], delivered: bool, destination: House = null) -> bool:
	if delivered and destination != null and (not _depots.has(destination) or not destination.is_main_nest or not can_deposit(destination, cargo_size(cargo))):
		return false
	if delivered and destination == null and not can_deposit(null, cargo_size(cargo)):
		return false
	var stock: Dictionary = _main_stock if destination == null else _depots.get(destination, {})
	for item in cargo:
		var id: StringName = item.type.id
		_transit[id] -= item.amount
		if delivered:
			stock[id] = int(stock.get(id, 0)) + item.amount
		else:
			_amounts[id] -= item.amount
	if not cargo.is_empty():
		_notify()
	return true

static func cargo_size(cargo: Array[ResourceAmount]) -> int:
	var count := 0
	for item in cargo:
		count += item.amount
	return count

func _withdraw(id: StringName, count: int, main_only: bool = false) -> void:
	_amounts[id] -= count
	var from_main: int = mini(_main_stock[id], count)
	_main_stock[id] -= from_main
	var remaining: int = count - from_main
	if remaining == 0:
		return
	for house in _depots:
		if main_only and not house.is_main_nest:
			continue
		var stock: Dictionary = _depots[house]
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
