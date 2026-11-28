class_name ColonyLogistics
extends Node

const TIMING := preload("res://game/navigation/navigation_timing.gd")
## Owns warehouse membership and routes. WorldInventory owns the stock ledger.

var main_nest: House
var construction: ConstructionService
var cargo_receiver: CargoShip
var inventory: WorldInventory
var navigation: RouteService
var _depots: Array[House] = []
var _canteens: Array[Canteen] = []
var _fields: Dictionary[Building, NavigationField] = {}
signal shipment_delivered(target: Building, type: ResourceType, amount: int)
signal export_delivered(source: House, type: ResourceType, amount: int)
signal stock_transferred(source: House, target: Building, type: ResourceType, amount: int)

func configure(stock: WorldInventory, routes: RouteService, registry: BuildingRegistry) -> void:
	inventory = stock
	navigation = routes
	registry.added.connect(_add_building)
	registry.removed.connect(_remove_building)

func _add_building(building: Building) -> void:
	if building is Canteen and building.colony_owned:
		_canteens.append(building)
		inventory.register_depot(building)
	if not building is House:
		return
	var house: House = building as House
	if not is_instance_valid(main_nest):
		main_nest = house
		house.is_main_nest = true
	else:
		_depots.append(house)
		inventory.register_depot(house)
	house.refresh_appearance()

func _remove_building(building: Building) -> void:
	if building is Canteen and _canteens.has(building):
		_canteens.erase(building)
		_fields.erase(building)
		inventory.unregister_depot(building)
	if not building is House:
		return
	var house: House = building as House
	_fields.erase(house)
	if house == main_nest:
		main_nest = null
		if not _depots.is_empty():
			for candidate in _depots:
				if candidate.is_main_nest:
					main_nest = candidate
					break
			if main_nest == null:
				main_nest = _depots.front()
			_depots.erase(main_nest)
			main_nest.is_main_nest = true
			main_nest.refresh_appearance()
			inventory.unregister_depot(main_nest)
	else:
		_depots.erase(house)
		inventory.unregister_depot(house)

func owns(building: Building) -> bool:
	if not is_instance_valid(building):
		return false
	if building is CargoShip:
		return building == cargo_receiver and building.is_inside_tree() and building.accepting_cargo
	if building is Canteen:
		return _canteens.has(building)
	return building is House and (building == main_nest or _depots.has(building))

## A worker's cargo goes only to the storage of the nest it lives in.
func accepts_home(house: House, count: int) -> bool:
	return owns(house) and inventory.can_deposit(null if house == main_nest else house, count)

func can_remove(house: House) -> bool:
	return house != main_nest and inventory.depot_fill(house) == 0

func closest_depot(cell: Vector2i, count: int) -> House:
	var best: House
	var lowest := INF
	if is_instance_valid(main_nest) and inventory.can_deposit(null, count):
		lowest = _field(main_nest).cost(cell)
		if is_finite(lowest):
			best = main_nest
	for house in _depots:
		if not inventory.can_deposit(house, count):
			continue
		var cost: float = _field(house).cost(cell)
		if cost < lowest:
			lowest = cost
			best = house
	return best

func construction_sources(entries: Array[Vector2i], removed: Array[Building] = []) -> Array[House]:
	var grid: TileGrid = navigation.snapshot()
	var sources: Array[House] = []
	for house: House in [main_nest] + _depots:
		if not owns(house) or not house.funds_construction or removed.has(house):
			continue
		for entry in entries:
			if house.entry_cells().any(func(cell: Vector2i) -> bool: return grid.connected(cell, entry)):
				sources.append(house)
				break
	return sources

func route_to(house: Building, cell: Vector2i) -> Route:
	return navigation.make_route(_field(house).path(cell)) if owns(house) else Route.invalid()

func field_to(house: House) -> NavigationField:
	return _field(house) if owns(house) else null

func deposit(house: House, cargo: Array[ResourceAmount]) -> bool:
	return owns(house) and inventory.deposit(store_of(house), cargo)

## Every owned nest; the first base is main_nest and is stored under the null key in WorldInventory.
func nests() -> Array[House]:
	var list: Array[House] = []
	if owns(main_nest):
		list.append(main_nest)
	for house in _depots:
		list.append(house)
	return list

## Key used by WorldInventory for this nest's stock: null for the first base.
func store_of(house: House) -> House:
	return null if house == main_nest else house

func _order_types() -> Array[ResourceType]:
	var list: Array[ResourceType] = []
	for type in inventory.registered_types():
		if type.id != WorldInventory.CURRENCY_ID:
			list.append(type)
	return list

func _incoming_total(house: House) -> int:
	var total := 0
	for count in house.incoming.values():
		total += int(count)
	return total

func order_for(house: House, type: ResourceType) -> Dictionary:
	return house.order_of(str(type.id))

## Units a nest still wants: refill up to max once stock (plus incoming) drops below min,
## plus any one-time request not yet on its way. Never more than free space.
func order_need(house: Building, type: ResourceType, accept_surplus := false) -> int:
	if house is CargoShip:
		return house.need(type) if owns(house) else 0
	if not owns(house):
		return 0
	if house is Canteen:
		return house.food_needed(inventory.depot_quantity(house, type), accept_surplus) if type.id == WorldInventory.FOOD_ID else 0
	var id: String = str(type.id)
	if int(house.requests.get(id, 0)) < 0:
		return 0
	var order: Dictionary = order_for(house, type)
	var have: int = inventory.stock_of(store_of(house), type) + int(house.incoming.get(id, 0))
	var wanted := 0
	if accept_surplus or have < int(order.min):
		wanted = int(order.max) - have
	wanted = maxi(wanted, int(house.requests.get(id, 0)) - int(house.incoming.get(id, 0)))
	var room: int = inventory.free_space(store_of(house)) - _incoming_total(house)
	return maxi(0, mini(wanted, room))

## Units a nest can give away without dropping below its own order minimum.
func order_surplus(house: House, type: ResourceType) -> int:
	var minimum: int = int(order_for(house, type).get("min", 0))
	var stock := inventory.stock_of(store_of(house), type)
	return maxi(0, stock - minimum)

## Refill below a receiver's minimum, or distribute an overflowing donor's stock
## to any warehouse below its maximum. Manual shipments still need physical room.
func transfer_amount(source: House, target: Building, type: ResourceType) -> int:
	if type == null or source == target or not owns(source) or not owns(target):
		return 0
	var stock := inventory.stock_of(store_of(source), type)
	var overflow: bool = stock > int(order_for(source, type).max)
	var wanted := order_need(target, type, overflow)
	var exported := maxi(0, -int(source.requests.get(str(type.id), 0)))
	if exported > 0 and target is House and int(target.requests.get(str(type.id), 0)) >= 0:
		var room := inventory.free_space(store_of(target)) - _incoming_total(target)
		wanted = maxi(wanted, mini(exported, room))
	return maxi(0, mini(mini(order_surplus(source, type), wanted), inventory.available(type)))

## Base nests that fund construction keep their stock while a site still lacks materials.
func construction_pending() -> bool:
	return construction != null and construction.sites.any(func(site) -> bool: return site.active and not site.supplied())

class StockOrder:
	var source: House
	var target: Building
	var type: ResourceType
	var amount: int
	var pickup: Route

	func _init(origin: House, destination: Building, resource: ResourceType, quantity: int, approach: Route) -> void:
		source = origin
		target = destination
		type = resource
		amount = quantity
		pickup = approach

## Best (source, target) pair for one trip. Flow fields score candidates in constant time;
## only the winning pickup route is reconstructed. can_collect receives pickup and delivery costs,
## the carrier's start cell, and the target entrance cell.
func nearest_order(from_cell: Vector2i, capacity: int, can_collect: Callable) -> StockOrder:
	if not TIMING.enabled: return _nearest_order(from_cell, capacity, can_collect)
	TIMING.begin(&"carrier_order")
	var result := _nearest_order(from_cell, capacity, can_collect)
	TIMING.end()
	return result

func _nearest_order(from_cell: Vector2i, capacity: int, can_collect: Callable) -> StockOrder:
	var best: StockOrder
	var lowest := INF
	var houses := nests()
	var targets: Array[Building] = []
	targets.assign(houses)
	targets.append_array(_canteens)
	if owns(cargo_receiver):
		targets.append(cargo_receiver)
	var types := _order_types()
	var pending := construction_pending()
	var surplus_by_type: Dictionary[ResourceType, Dictionary] = {}
	for type in types:
		var sources: Dictionary[House, int] = {}
		for house in houses:
			if pending and house.funds_construction: continue
			var surplus := order_surplus(house, type)
			if surplus > 0: sources[house] = surplus
		if not sources.is_empty(): surplus_by_type[type] = sources
	for target in targets:
		for type in surplus_by_type:
			var sources: Dictionary[House, int] = surplus_by_type[type]
			for source in sources:
				var need := mini(transfer_amount(source, target, type), capacity)
				if need <= 0:
					continue
				var source_field: NavigationField = _field(source)
				var pickup_cost: float = source_field.cost(from_cell)
				if not is_finite(pickup_cost):
					continue
				var pickup_end := source_field.destination(from_cell)
				var target_field: NavigationField = _field(target)
				var delivery_cost: float = target_field.cost(pickup_end)
				var cost: float = pickup_cost + delivery_cost
				if cost < lowest and can_collect.call(pickup_cost, delivery_cost, from_cell, target_field.destination(pickup_end)):
					lowest = cost
					best = StockOrder.new(source, target, type, need, null)
	if best != null:
		best.pickup = route_to(best.source, from_cell)
	return best

func _field(house: Building) -> NavigationField:
	if house is CargoShip:
		return navigation.reverse_field(house.entry_cells())
	var field: NavigationField = _fields.get(house)
	if field == null or field.revision != navigation.revision:
		field = navigation.reverse_field(house.entry_cells(), field)
		_fields[house] = field
	return field
