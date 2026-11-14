class_name ColonyLogistics
extends Node
## Owns warehouse membership and routes. WorldInventory owns the stock ledger.

var main_nest: House
var construction: ConstructionService
var inventory: WorldInventory
var navigation: RouteService
var _depots: Array[House] = []
var _fields: Dictionary[House, NavigationField] = {}
var _revision := -1

func configure(stock: WorldInventory, routes: RouteService, registry: BuildingRegistry) -> void:
	inventory = stock
	navigation = routes
	registry.added.connect(_add_building)
	registry.removed.connect(_remove_building)

func _add_building(building: Building) -> void:
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

func owns(house: House) -> bool:
	return is_instance_valid(house) and (house == main_nest or _depots.has(house))

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

func closest_base(cell: Vector2i, count: int) -> House:
	var best: House
	var lowest := INF
	for house in [main_nest] + _depots:
		if not owns(house) or not house.is_main_nest:
			continue
		if not inventory.can_deposit(null if house == main_nest else house, count):
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

func route_to(house: House, cell: Vector2i) -> Route:
	return navigation.make_route(_field(house).path(cell)) if is_instance_valid(house) and (house == main_nest or _depots.has(house)) else Route.invalid()

func deposit(house: House, cargo: Array[ResourceAmount]) -> bool:
	return owns(house) and inventory.deposit(null if house == main_nest else house, cargo)

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
func order_need(house: House, type: ResourceType) -> int:
	if not owns(house):
		return 0
	var id: String = str(type.id)
	var order: Dictionary = order_for(house, type)
	var have: int = inventory.stock_of(store_of(house), type) + int(house.incoming.get(id, 0))
	var wanted := 0
	if not order.is_empty() and have < int(order.min):
		wanted = int(order.max) - have
	wanted = maxi(wanted, int(house.requests.get(id, 0)) - int(house.incoming.get(id, 0)))
	var room: int = inventory.free_space(store_of(house)) - _incoming_total(house)
	return maxi(0, mini(wanted, room))

## Units a nest can give away without dropping below its own order minimum.
func order_surplus(house: House, type: ResourceType) -> int:
	var minimum: int = int(order_for(house, type).get("min", 0))
	return inventory.stock_of(store_of(house), type) - minimum

## Base nests that fund construction keep their stock while a site still lacks materials.
func construction_pending() -> bool:
	return construction != null and construction.sites.any(func(site) -> bool: return site.active and not site.supplied())

func _source_allowed(house: House) -> bool:
	return not (house.funds_construction and construction_pending())

## Best (source, target) pair for one trip. A trip carries what the target needs, up to the carrier's
## capacity and the source's surplus. can_collect(pickup, delivery) checks the carrier's energy.
func nearest_order(from_cell: Vector2i, capacity: int, can_collect: Callable) -> Dictionary:
	var best := {}
	var lowest := INF
	for target in nests():
		for type in _order_types():
			var need: int = mini(order_need(target, type), capacity)
			if need <= 0:
				continue
			for source in nests():
				var amount: int = mini(need, order_surplus(source, type))
				if source == target or not _source_allowed(source) or amount <= 0:
					continue
				var pickup: Route = route_to(source, from_cell)
				if not pickup.is_valid():
					continue
				var delivery: Route = route_to(target, pickup.cells.back())
				if not delivery.is_valid() or not can_collect.call(pickup, delivery):
					continue
				var cost: float = pickup.cost + delivery.cost
				if cost < lowest:
					lowest = cost
					best = {"source": source, "target": target, "type": type, "amount": amount, "pickup": pickup}
	return best

func _field(house: House) -> NavigationField:
	if _revision != navigation.revision:
		_fields.clear()
		_revision = navigation.revision
	if not _fields.has(house):
		_fields[house] = navigation.reverse_field(house.entry_cells())
	return _fields[house]
