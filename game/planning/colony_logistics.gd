class_name ColonyLogistics
extends Node
## Owns warehouse membership and routes. WorldInventory owns the stock ledger.

var main_nest: House
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
	else:
		_depots.append(house)
		inventory.register_depot(house)

func _remove_building(building: Building) -> void:
	if not building is House:
		return
	var house: House = building as House
	_fields.erase(house)
	if house == main_nest:
		main_nest = null
		if not _depots.is_empty():
			main_nest = _depots.pop_front()
			inventory.unregister_depot(main_nest)
	else:
		_depots.erase(house)
		inventory.unregister_depot(house)

func can_remove(house: House) -> bool:
	return house != main_nest and inventory.depot_fill(house) == 0

func closest_depot(cell: Vector2i, count: int) -> House:
	var best: House
	var lowest := INF
	if is_instance_valid(main_nest):
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

func route_to(house: House, cell: Vector2i) -> Route:
	return navigation.make_route(_field(house).path(cell)) if is_instance_valid(house) and (house == main_nest or _depots.has(house)) else Route.invalid()

func deposit(house: House, cargo: Array[ResourceAmount]) -> bool:
	return is_instance_valid(house) and inventory.deposit(null if house == main_nest else house, cargo)

func ready_to_dispatch(house: House) -> bool:
	return _depots.has(house) and house.auto_dispatch and inventory.depot_fill(house) * 100 >= house.storage_capacity * house.dispatch_threshold

func _field(house: House) -> NavigationField:
	if _revision != navigation.revision:
		_fields.clear()
		_revision = navigation.revision
	if not _fields.has(house):
		_fields[house] = navigation.reverse_field(house.entry_cells())
	return _fields[house]
