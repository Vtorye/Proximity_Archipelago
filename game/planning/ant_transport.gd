class_name AntTransport
extends RefCounted
## Owns cargo, reservations for incoming orders, and pickup and delivery decisions.

var ant: AntAgent
var cargo: Array[ResourceAmount] = []
var carrying := false
var shipment := false
var pickup_source: Building
var delivery_nest: Building
var order_target: Building
var _order_type: ResourceType
var _export_source: House

func decide_pickup(foodless: bool) -> void:
	var cell: Vector2i = ant.route_service.world_to_cell(ant.global_position)
	var order: ColonyLogistics.StockOrder = ant.logistics.nearest_order(cell, ant.carry_capacity, can_start_pickup)
	if order != null:
		pickup_source = order.source
		order_target = order.target
		_order_type = order.type
		ant._walk(order.pickup, &"pickup")
		return
	pickup_source = null
	order_target = null
	_order_type = null
	if foodless:
		ant._wander()
	elif not ant.needs.can_afford(ant.planner.escape_energy(cell, ant.speed) + ant.needs.rules.travel_reserve):
		ant._seek_food()
	elif is_instance_valid(ant.home) and (cell - ant.planner.accessible_entry(ant.home)).length_squared() > 4:
		ant._go_home()
	else:
		ant._wander()

func can_start_pickup(pickup_cost: float, delivery_cost: float, start_cell: Vector2i, delivery_end: Vector2i) -> bool:
	var approach := ant.planner.approach_energy(ant.global_position, start_cell, ant.speed)
	var energy: float = approach + ant.planner.travel_energy(pickup_cost, ant.speed)
	energy += ant.planner.travel_energy(delivery_cost, ant.speed * ant.planner.carry_speed_ratio)
	if ant._is_foodless():
		return ant.needs.satiety > energy
	return ant.needs.can_afford(energy + ant.planner.escape_energy(delivery_end, ant.speed))

func load_pickup() -> void:
	var source: House = pickup_source as House
	var target: Building = order_target
	var type: ResourceType = _order_type
	pickup_source = null
	# Other couriers may have loaded or reserved room while this one was walking.
	var amount := mini(ant.carry_capacity, ant.logistics.transfer_amount(source, target, type))
	if amount > 0:
		cargo = ant.planner.inventory.take_for_order(ant.logistics.store_of(source), type, amount)
		shipment = not cargo.is_empty()
		if shipment:
			pickup_source = source
			source.show_stock_transfer(cargo, false)
			_export_source = source if int(source.requests.get(str(type.id), 0)) < 0 else null
			source.record_export(str(type.id), WorldInventory.cargo_size(cargo))
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
	var meal_due: bool = meal_would_enable_delivery or ant.needs.satiety <= meal_energy + ant.needs.safety_margin + ant.needs.rules.travel_reserve
	if meal_due and ant.needs.satiety > meal_energy and not ant._is_foodless():
		ant._seek_food()
	elif ant.role == AntAgent.Role.WORKER:
		_idle_with_cargo()
	else:
		ant._set_status(AntAgent.Status.WAITING_FOR_FOOD)
		ant._timer = ant.definition.retry_seconds

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
	var approach := ant.planner.approach_energy(ant.global_position, from_cell, loaded_speed)
	var energy: float = ant.planner.travel_energy(route.cost, loaded_speed) + approach
	if not ant._is_foodless():
		energy += ant.planner.escape_energy(route.cells.back(), ant.speed)
	return energy

func _order_target_accepts(count: int) -> bool:
	if not is_instance_valid(order_target) or not ant.logistics.owns(order_target):
		return false
	if order_target is CargoShip:
		return order_target.accepts(cargo)
	if order_target is Canteen:
		return ant.planner.inventory.can_deliver_food(order_target, cargo)
	return ant.planner.inventory.can_deposit(ant.logistics.store_of(order_target), count)

## Units en route to the order target count toward its minimum, so no second trip is sent for them.
func _set_incoming(delta: int) -> void:
	if not is_instance_valid(order_target) or cargo.is_empty():
		return
	if order_target is Canteen:
		order_target.incoming_food = maxi(0, order_target.incoming_food + delta)
		return
	var key: String = str(cargo[0].type.id)
	order_target.incoming[key] = maxi(0, int(order_target.incoming.get(key, 0)) + delta)

func unload() -> void:
	if shipment:
		if not _receive_shipment():
			# Destination lost its room while this load was en route; keep the cargo and retry.
			deliver()
			return
	elif not ant.logistics.deposit(delivery_nest as House, cargo):
		deliver()
		return
	else:
		(delivery_nest as House).show_stock_transfer(cargo, true)
	_clear_cargo()
	ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
	ant._go_home()

func _receive_shipment() -> bool:
	if not is_instance_valid(delivery_nest) or not ant.logistics.owns(delivery_nest):
		return false
	var count := WorldInventory.cargo_size(cargo)
	var type := cargo[0].type
	var inventory: WorldInventory = ant.planner.inventory
	if delivery_nest is CargoShip:
		if not delivery_nest.receive(cargo, inventory):
			return false
	else:
		var store: Building = delivery_nest if delivery_nest is Canteen else ant.logistics.store_of(delivery_nest)
		if not inventory.close_shipment(cargo, true, store):
			return false
		if delivery_nest is House:
			delivery_nest.show_stock_transfer(cargo, true)
			if delivery_nest == order_target:
				delivery_nest.fulfil(str(type.id), count)
		else:
			delivery_nest.show_stock_change(type, count)
	_set_incoming(-count)
	if delivery_nest == order_target and delivery_nest is Canteen:
		delivery_nest.fulfil_food_request(count)
	ant.logistics.shipment_delivered.emit(delivery_nest, type, count)
	if is_instance_valid(pickup_source):
		ant.logistics.stock_transferred.emit(pickup_source as House, delivery_nest, type, count)
	_notify_export()
	return true

func _clear_cargo() -> void:
	_export_source = null
	pickup_source = null
	cargo.clear()
	shipment = false
	order_target = null
	delivery_nest = null
	carrying = false

func _notify_export() -> void:
	if is_instance_valid(_export_source):
		ant.logistics.export_delivered.emit(_export_source, cargo[0].type, WorldInventory.cargo_size(cargo))

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
	state["export_source"] = buildings.find(_export_source)
	if is_instance_valid(order_target):
		state["order_target"] = buildings.find(order_target)
		state["order_type"] = str(_order_type.id) if _order_type != null else ""

func restore_state(state: Dictionary, buildings: Array[Building]) -> void:
	cargo = ResourceAmount.unpack(state.cargo, ant.planner.inventory.type_by_id)
	pickup_source = buildings[state.pickup] if state.pickup >= 0 else null
	delivery_nest = buildings[state.delivery] if state.delivery >= 0 else null
	carrying = state._carrying
	shipment = state._shipment
	var export_index: int = int(state.get("export_source", -1))
	_export_source = buildings[export_index] as House if export_index >= 0 and export_index < buildings.size() else null
	if int(state.get("order_target", -1)) >= 0:
		order_target = buildings[state.order_target]
		_order_type = ant.planner.inventory.type_by_id(StringName(state.get("order_type", "")))
		if shipment and order_target != null:
			_set_incoming(WorldInventory.cargo_size(cargo))
