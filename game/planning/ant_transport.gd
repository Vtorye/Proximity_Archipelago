class_name AntTransport
extends RefCounted
## Owns cargo, reservations for incoming orders, and pickup and delivery decisions.

var ant: AntAgent
var cargo: Array[ResourceAmount] = []
var carrying := false
var shipment := false
var pickup_source: Building
var delivery_nest: House
var order_target: House
var _order_type: ResourceType
var _order_amount := 0

func decide_pickup(foodless: bool) -> void:
	var cell: Vector2i = ant.route_service.world_to_cell(ant.global_position)
	var order: ColonyLogistics.StockOrder = ant.logistics.nearest_order(cell, ant.carry_capacity, can_start_pickup)
	if order != null:
		pickup_source = order.source
		order_target = order.target
		_order_type = order.type
		_order_amount = order.amount
		ant._walk(order.pickup, &"pickup")
		return
	pickup_source = null
	order_target = null
	_order_type = null
	_order_amount = 0
	if foodless:
		ant._wander()
	elif not ant.needs.can_afford(ant.planner.escape_energy(cell, ant.speed) + 2.0):
		ant._seek_food()
	elif is_instance_valid(ant.home) and (cell - ant.planner.accessible_entry(ant.home)).length_squared() > 4:
		ant._go_home()
	else:
		ant._wander()

func can_start_pickup(pickup: Route, delivery: Route) -> bool:
	if not delivery.is_valid():
		return false
	var cell: Vector2i = pickup.cells.front()
	var approach: float = ant.global_position.distance_to(ant.route_service.cell_to_world(cell)) * ant.route_service.entry_cost(cell) / ant.speed
	var energy: float = approach + ant.planner.travel_energy(pickup.cost, ant.speed)
	energy += ant.planner.travel_energy(delivery.cost, ant.speed * ant.planner.carry_speed_ratio)
	if ant._is_foodless():
		return ant.needs.satiety > energy
	return ant.needs.can_afford(energy + ant.planner.escape_energy(delivery.cells.back(), ant.speed))

func load_pickup() -> void:
	var source: House = pickup_source as House
	var target: House = order_target
	var type: ResourceType = _order_type
	var amount: int = _order_amount
	pickup_source = null
	if _order_still_valid(source, target, type, amount):
		cargo = ant.planner.inventory.take_for_order(ant.logistics.store_of(source), type, amount)
		shipment = not cargo.is_empty()
	if cargo.is_empty():
		# Stock or need changed while this carrier was en route.
		order_target = null
		ant._decide()
	else:
		_set_incoming(WorldInventory.cargo_size(cargo))
		deliver()

func deliver() -> void:
	carrying = true
	var cell: Vector2i = ant.route_service.world_to_cell(ant.global_position)
	var count: int = WorldInventory.cargo_size(cargo)
	if shipment:
		# Orders go to their target; if it filled up meanwhile, to the nearest nest with room.
		delivery_nest = order_target if _order_target_accepts(count) else ant.logistics.closest_depot(cell, count)
	elif ant.role == AntAgent.Role.WORKER:
		# Workers return only to the storage of the nest they live in.
		delivery_nest = _home_storage(count)
	else:
		delivery_nest = ant.logistics.closest_depot(cell, count)
	var route: Route = ant.logistics.route_to(delivery_nest, cell)
	if route.is_valid() and _can_deliver(route, cell):
		ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
		ant._walk(route, &"delivery")
		return
	var meal_energy: float = ant.planner.escape_energy(cell, ant.speed * ant.planner.carry_speed_ratio)
	var meal_would_enable_delivery: bool = route.is_valid() and _delivery_energy(route, cell) + ant.needs.safety_margin <= ant.needs.capacity
	var meal_due: bool = meal_would_enable_delivery or ant.needs.satiety <= meal_energy + ant.needs.safety_margin + 2.0
	if meal_due and ant.needs.satiety > meal_energy and not ant._is_foodless():
		ant._seek_food()
	elif ant.role == AntAgent.Role.WORKER:
		_idle_with_cargo()
	else:
		ant._set_status(AntAgent.Status.WAITING_FOR_FOOD)
		ant._timer = 1.0

## Home storage when it has room for this cargo, otherwise null.
func _home_storage(count: int) -> House:
	if not is_instance_valid(ant.home) or not ant.logistics.accepts_home(ant.home, count):
		return null
	return ant.home

## Holds cargo near home until storage frees up; _decide() retries delivery on each arrival.
func _idle_with_cargo() -> void:
	ant._set_waiting_reason(WorkPlan.WaitReason.STORAGE_FULL)
	var cell: Vector2i = ant.route_service.world_to_cell(ant.global_position)
	var origin: Vector2i = ant.planner.accessible_entry(ant.home) if is_instance_valid(ant.home) else cell
	var nearby := ant.route_service.snapshot().neighbors(cell).filter(func(next: Vector2i) -> bool:
		return absi(next.x - origin.x) + absi(next.y - origin.y) <= 2)
	if nearby.is_empty():
		ant._go_home()
	else:
		ant._walk(ant.route_service.make_route([cell, nearby.pick_random()]), &"wander")

func _can_deliver(route: Route, from_cell: Vector2i) -> bool:
	var energy: float = _delivery_energy(route, from_cell)
	return ant.needs.satiety > energy if ant._is_foodless() else ant.needs.can_afford(energy)

func _delivery_energy(route: Route, from_cell: Vector2i) -> float:
	var loaded_speed: float = ant.speed * ant.planner.carry_speed_ratio
	var approach: float = ant.global_position.distance_to(ant.route_service.cell_to_world(from_cell)) * ant.route_service.entry_cost(from_cell) / loaded_speed
	var energy: float = ant.planner.travel_energy(route.cost, loaded_speed) + approach
	if not ant._is_foodless():
		energy += ant.planner.escape_energy(route.cells.back(), ant.speed)
	return energy

func _order_target_accepts(count: int) -> bool:
	return is_instance_valid(order_target) and ant.logistics.owns(order_target) and ant.planner.inventory.can_deposit(ant.logistics.store_of(order_target), count)

## An order is valid while its source still has surplus and its target still needs the amount.
func _order_still_valid(source: House, target: House, type: ResourceType, amount: int) -> bool:
	return (
		type != null and amount > 0
		and is_instance_valid(source) and source.is_inside_tree() and ant.logistics.owns(source)
		and is_instance_valid(target) and ant.logistics.owns(target)
		and ant.logistics.order_surplus(source, type) >= amount
		and ant.logistics.order_need(target, type) >= amount
	)

## Units en route to the order target count toward its minimum, so no second trip is sent for them.
func _set_incoming(delta: int) -> void:
	if not is_instance_valid(order_target) or cargo.is_empty():
		return
	var key: String = str(cargo[0].type.id)
	order_target.incoming[key] = maxi(0, int(order_target.incoming.get(key, 0)) + delta)

func unload() -> void:
	if shipment:
		if ant.logistics.owns(delivery_nest) and ant.planner.inventory.close_shipment(cargo, true, ant.logistics.store_of(delivery_nest)):
			if delivery_nest == order_target:
				order_target.fulfil(str(cargo[0].type.id), WorldInventory.cargo_size(cargo))
			_set_incoming(-WorldInventory.cargo_size(cargo))
			_clear_cargo()
			ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
			ant._go_home()
			return
		# Destination lost its room while this load was en route; keep the cargo and retry.
		deliver()
		return
	if not ant.logistics.deposit(delivery_nest, cargo):
		deliver()
		return
	_clear_cargo()
	ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
	ant._go_home()

func _clear_cargo() -> void:
	cargo.clear()
	shipment = false
	order_target = null
	delivery_nest = null
	carrying = false

func discard() -> void:
	if shipment:
		ant.planner.inventory.close_shipment(cargo, false)
		_set_incoming(-WorldInventory.cargo_size(cargo))
	_clear_cargo()

func capture_state(state: Dictionary, buildings: Array[Building]) -> void:
	state["_carrying"] = carrying
	state["_shipment"] = shipment
	state["cargo"] = ResourceAmount.pack(cargo)
	state["pickup"] = buildings.find(pickup_source)
	state["delivery"] = buildings.find(delivery_nest)

func restore_state(state: Dictionary, buildings: Array[Building]) -> void:
	cargo = ResourceAmount.unpack(state.cargo, ant.planner.inventory.type_by_id)
	pickup_source = buildings[state.pickup] if state.pickup >= 0 else null
	delivery_nest = buildings[state.delivery] as House if state.delivery >= 0 else null
	carrying = state._carrying
	shipment = state._shipment
