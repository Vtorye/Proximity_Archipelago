class_name AntAgent
extends Node2D
## Executes plans; needs, route execution, and assignment policy are separate objects.

enum Role { WORKER, CARRIER, WARRIOR }
enum DeathCause { STARVATION, DEMOLISHED, OTHER, PLAYER, ENEMY, TRAP }
enum Status { HOME, WALKING, WORKING, EATING, WAITING_FOR_FOOD, DEAD, WANDERING, CONSTRUCTING, GUARDING, FIGHTING }
signal work_completed(human: Node2D, workplace: Node2D)
signal died(human: Node2D, cause: DeathCause)
signal status_changed(status: Status)
signal cell_changed(old: Vector2i, next: Vector2i)
signal waiting_changed

@export var profile: AntProfile
@export var speed := 24.0
@export var work_time := 3.0
@export_range(1, 100) var carry_capacity := 2
var combat: AntCombat
var max_health := 1
var health := 1
var attack_damage := 1
var construction: AntConstruction
var role: Role = Role.WORKER
var home: House
var planner: TripPlanner
var route_service: RouteService
var logistics: ColonyLogistics
var needs := AntNeeds.new()
var motion := AntMotion.new()
var status: Status = Status.HOME
var current_workplace: Workplace
var _plan: WorkPlan
var _meal: StockReservation
var _destination: StringName = &"home"
var _timer := 0.0
var departure_delay := 0.0
var _carrying := false
var cargo: Array[ResourceAmount] = []
var _shipment := false
var _delivery_nest: House
var _pickup_source: Building
## The order being fetched or carried: target nest, resource, and amount.
var _order_target: House
var _order_type: ResourceType
var _order_amount := 0
var _angle := 0.0
var _animation_time := 0.0
var _last_direction := Vector2.UP
var _waiting_for_work := false
var _waiting_reason: WorkPlan.WaitReason = WorkPlan.WaitReason.NONE
var waiting_reason: WorkPlan.WaitReason:
	get: return _waiting_reason
var _reconsider_queued := false
var _navigation_pending := false

func apply_profile() -> void:
	if profile == null: return
	needs.configure(profile.satiety_capacity)
	speed = profile.speed
	work_time = profile.work_seconds
	carry_capacity = profile.carry_capacity
	max_health = profile.health
	health = max_health
	attack_damage = profile.damage

func configure(nest: House, policy: TripPlanner, navigation: RouteService, storage: ColonyLogistics) -> void:
	home = nest
	planner = policy
	route_service = navigation
	motion.navigation = navigation
	logistics = storage

func _ready() -> void:
	assert(home != null and planner != null and route_service != null, "Ant dependencies must be configured before entering the tree")
	route_service.navigation_changed.connect(_on_navigation_changed)
	route_service.food_sources_changed.connect(_on_food_sources_changed)
	planner.opportunities_changed.connect(_on_work_opportunities_changed)
	_timer = departure_delay + randf_range(0.3, 0.5)
	refresh_meal_reservation()

func refresh_meal_reservation() -> void:
	if _is_foodless():
		planner.inventory.release(_meal)
		_meal = null
	elif _meal == null or not _meal.active:
		_meal = planner.reserve_meal()

func _is_foodless() -> bool:
	return not planner.food_within_range(route_service.world_to_cell(global_position), speed, needs.capacity)

func _exit_tree() -> void:
	if combat != null: combat.leave_tower()
	if construction != null: construction.release()
	_release_work()
	if planner != null and is_instance_valid(planner.inventory):
		_discard_cargo()
		planner.inventory.release(_meal)
	if is_instance_valid(home):
		home.remove_resident(self)

func _physics_process(delta: float) -> void:
	if status == Status.DEAD:
		return
	var rate: float = AntNeeds.REST_RATE
	if status == Status.WALKING:
		rate = AntNeeds.WALK_RATE
	elif status in [Status.WORKING, Status.CONSTRUCTING]:
		rate = AntNeeds.WORK_RATE
	elif status == Status.EATING:
		rate = AntNeeds.EAT_RATE
	needs.consume(delta, rate)
	_animation_time += delta
	if needs.satiety <= 0.0:
		die(DeathCause.STARVATION)
		return
	if combat != null and combat.physics(delta):
		queue_redraw()
		return
	match status:
		Status.HOME:
			_timer -= delta
			if _timer <= 0.0:
				_decide()
		Status.WALKING:
			var before: Vector2 = global_position
			global_position = motion.step(global_position, speed * (TripPlanner.CARRY_SPEED_RATIO if _carrying else 1.0), delta)
			var old_cell: Vector2i = route_service.world_to_cell(before)
			var next_cell: Vector2i = route_service.world_to_cell(global_position)
			if old_cell != next_cell:
				cell_changed.emit(old_cell, next_cell)
				if status == Status.DEAD: return
			if before.distance_squared_to(global_position) > 0.0001:
				_last_direction = (global_position - before).normalized()
			if motion.finished:
				_arrive()
		Status.WORKING:
			_timer -= delta
			if not is_instance_valid(current_workplace) or not current_workplace.is_inside_tree():
				_seek_food()
			elif _timer <= 0.0:
				if not current_workplace.complete_cycle(self, true):
					# Contended ingredients must not trap the worker in unbudgeted repeat cycles.
					_seek_food()
					return
				cargo = current_workplace.take_output(carry_capacity)
				work_completed.emit(self, current_workplace)
				if not cargo.is_empty():
					_release_work()
					_deliver()
				elif _plan != null and _plan.foodless and not _can_recover():
					_timer = work_time
				else:
					_release_work()
					_go_home()
		Status.CONSTRUCTING:
			construction.tick(delta)
		Status.EATING:
			_timer -= delta
			if _timer <= 0.0:
				if planner.inventory.consume(_meal):
					needs.eat()
				_meal = null
				if role == Role.WARRIOR:
					_set_status(Status.HOME)
					_timer = 0.3
				elif cargo.is_empty() and not (construction != null and construction.has_cargo()):
					_carrying = false
					_go_home()
				else:
					_deliver()
		Status.WANDERING:
			_timer -= delta
			if _timer <= 0.0:
				_decide()
		Status.WAITING_FOR_FOOD:
			_timer -= delta
			if _timer <= 0.0:
				_decide()
	queue_redraw()

func _decide() -> void:
	if combat != null and role == Role.WARRIOR:
		combat.decide()
		return
	if construction != null and construction.has_cargo():
		_deliver()
		return
	if not cargo.is_empty():
		_deliver()
		return
	var foodless: bool = _is_foodless()
	refresh_meal_reservation()
	if construction != null and status in [Status.HOME, Status.WAITING_FOR_FOOD, Status.WANDERING] and construction.decide(): return
	if role == Role.CARRIER:
		_decide_pickup(foodless)
		return
	if foodless:
		_carrying = false
	_plan = planner.plan_work(self, home, needs, speed, work_time, _meal, current_workplace)
	if _plan != null and _plan.waiting_for_slot:
		_waiting_for_work = true
		_set_waiting_reason(_plan.waiting_reason)
		_release_work()
		if global_position.distance_squared_to(route_service.cell_to_world(planner.accessible_entry(home))) > 0.01:
			_go_home()
		else:
			_set_status(Status.HOME)
			_timer = 0.75
	elif _plan != null:
		_waiting_for_work = false
		_set_waiting_reason(WorkPlan.WaitReason.NONE)
		current_workplace = _plan.workplace
		_walk(_plan.outward, &"work")
	else:
		_waiting_for_work = false
		_set_waiting_reason(WorkPlan.WaitReason.NONE)
		if foodless:
			_release_work()
			_wander()
		else:
			_seek_food()

func _decide_pickup(foodless: bool) -> void:
	var cell: Vector2i = route_service.world_to_cell(global_position)
	var order: Dictionary = logistics.nearest_order(cell, carry_capacity, _can_collect_order)
	if not order.is_empty():
		_pickup_source = order.source
		_order_target = order.target
		_order_type = order.type
		_order_amount = order.amount
		_walk(order.pickup, &"pickup")
		return
	_pickup_source = null
	_order_target = null
	_order_type = null
	_order_amount = 0
	if foodless:
		_wander()
	elif not needs.can_afford(planner.escape_energy(cell, speed) + 2.0):
		_seek_food()
	elif is_instance_valid(home) and (cell - planner.accessible_entry(home)).length_squared() > 4:
		_go_home()
	else:
		_wander()

func _can_collect_order(pickup: Route, delivery: Route) -> bool:
	return _can_start_pickup(pickup, delivery)

func _can_start_pickup(pickup: Route, delivery: Route) -> bool:
	if not delivery.is_valid():
		return false
	var cell: Vector2i = pickup.cells.front()
	var approach: float = global_position.distance_to(route_service.cell_to_world(cell)) * route_service.entry_cost(cell) / speed
	var energy: float = approach + planner.travel_energy(pickup.cost, speed)
	energy += planner.travel_energy(delivery.cost, speed * TripPlanner.CARRY_SPEED_RATIO)
	if _is_foodless():
		return needs.satiety > energy
	return needs.can_afford(energy + planner.escape_energy(delivery.cells.back(), speed))

func _load_pickup() -> void:
	var source: House = _pickup_source as House
	var target: House = _order_target
	var type: ResourceType = _order_type
	var amount: int = _order_amount
	_pickup_source = null
	if _order_still_valid(source, target, type, amount):
		cargo = planner.inventory.take_for_order(logistics.store_of(source), type, amount)
		_shipment = not cargo.is_empty()
	if cargo.is_empty():
		# Stock or need changed while this carrier was en route.
		_order_target = null
		_decide()
	else:
		_set_incoming(WorldInventory.cargo_size(cargo))
		_deliver()

func _deliver() -> void:
	if construction != null and construction.has_cargo():
		if not construction.resume():
			_set_status(Status.WAITING_FOR_FOOD)
			_timer = 1.0
		return
	_carrying = true
	var cell: Vector2i = route_service.world_to_cell(global_position)
	var count: int = WorldInventory.cargo_size(cargo)
	if _shipment:
		# Orders go to their target; if it filled up meanwhile, to the nearest nest with room.
		_delivery_nest = _order_target if _order_target_accepts(count) else logistics.closest_depot(cell, count)
	elif role == Role.WORKER:
		# Workers return only to the storage of the nest they live in.
		_delivery_nest = _home_storage(count)
	else:
		_delivery_nest = logistics.closest_depot(cell, count)
	var route: Route = logistics.route_to(_delivery_nest, cell)
	if route.is_valid() and _can_deliver(route, cell):
		_set_waiting_reason(WorkPlan.WaitReason.NONE)
		_walk(route, &"delivery")
		return
	var meal_energy: float = planner.escape_energy(cell, speed * TripPlanner.CARRY_SPEED_RATIO)
	var meal_would_enable_delivery: bool = route.is_valid() and _delivery_energy(route, cell) + AntNeeds.SAFETY_MARGIN <= needs.capacity
	var meal_due: bool = meal_would_enable_delivery or needs.satiety <= meal_energy + AntNeeds.SAFETY_MARGIN + 2.0
	if meal_due and needs.satiety > meal_energy and not _is_foodless():
		_seek_food()
	elif role == Role.WORKER:
		_idle_with_cargo()
	else:
		_set_status(Status.WAITING_FOR_FOOD)
		_timer = 1.0

## Home storage when it has room for this cargo, otherwise null.
func _home_storage(count: int) -> House:
	if not is_instance_valid(home) or not logistics.accepts_home(home, count):
		return null
	return home

## Holds cargo near home until storage frees up; _decide() retries delivery on each arrival.
func _idle_with_cargo() -> void:
	_set_waiting_reason(WorkPlan.WaitReason.STORAGE_FULL)
	var cell: Vector2i = route_service.world_to_cell(global_position)
	var origin: Vector2i = planner.accessible_entry(home) if is_instance_valid(home) else cell
	var nearby := route_service.snapshot().neighbors(cell).filter(func(next: Vector2i) -> bool:
		return absi(next.x - origin.x) + absi(next.y - origin.y) <= 2)
	if nearby.is_empty():
		_go_home()
	else:
		_walk(route_service.make_route([cell, nearby.pick_random()]), &"wander")

func _can_deliver(route: Route, from_cell: Vector2i) -> bool:
	var energy: float = _delivery_energy(route, from_cell)
	return needs.satiety > energy if _is_foodless() else needs.can_afford(energy)

func _delivery_energy(route: Route, from_cell: Vector2i) -> float:
	var loaded_speed: float = speed * TripPlanner.CARRY_SPEED_RATIO
	var approach: float = global_position.distance_to(route_service.cell_to_world(from_cell)) * route_service.entry_cost(from_cell) / loaded_speed
	var energy: float = planner.travel_energy(route.cost, loaded_speed) + approach
	if not _is_foodless():
		energy += planner.escape_energy(route.cells.back(), speed)
	return energy

func _order_target_accepts(count: int) -> bool:
	return is_instance_valid(_order_target) and logistics.owns(_order_target) and planner.inventory.can_deposit(logistics.store_of(_order_target), count)

## An order is valid while its source still has surplus and its target still needs the amount.
func _order_still_valid(source: House, target: House, type: ResourceType, amount: int) -> bool:
	return (
		type != null and amount > 0
		and is_instance_valid(source) and source.is_inside_tree() and logistics.owns(source)
		and is_instance_valid(target) and logistics.owns(target)
		and logistics.order_surplus(source, type) >= amount
		and logistics.order_need(target, type) >= amount
	)

## Units en route to the order target count toward its minimum, so no second trip is sent for them.
func _set_incoming(delta: int) -> void:
	if not is_instance_valid(_order_target) or cargo.is_empty():
		return
	var key: String = str(cargo[0].type.id)
	_order_target.incoming[key] = maxi(0, int(_order_target.incoming.get(key, 0)) + delta)

func _unload() -> void:
	if _shipment:
		if logistics.owns(_delivery_nest) and planner.inventory.close_shipment(cargo, true, logistics.store_of(_delivery_nest)):
			if _delivery_nest == _order_target:
				_order_target.fulfil(str(cargo[0].type.id), WorldInventory.cargo_size(cargo))
			_set_incoming(-WorldInventory.cargo_size(cargo))
			_clear_cargo()
			_set_waiting_reason(WorkPlan.WaitReason.NONE)
			_go_home()
			return
		# Destination lost its room while this load was en route; keep the cargo and retry.
		_deliver()
		return
	if not logistics.deposit(_delivery_nest, cargo):
		_deliver()
		return
	_clear_cargo()
	_set_waiting_reason(WorkPlan.WaitReason.NONE)
	_go_home()

func _clear_cargo() -> void:
	cargo.clear()
	_shipment = false
	_order_target = null
	_delivery_nest = null
	_carrying = false

func _discard_cargo() -> void:
	if _shipment:
		planner.inventory.close_shipment(cargo, false)
		_set_incoming(-WorldInventory.cargo_size(cargo))
	_clear_cargo()

func _wander() -> void:
	var cell: Vector2i = route_service.world_to_cell(global_position)
	var origin: Vector2i = planner.accessible_entry(home) if is_instance_valid(home) else cell
	var radius: int = maxi(2, absi(cell.x - origin.x) + absi(cell.y - origin.y))
	var neighbors: Array[Vector2i] = route_service.snapshot().neighbors(cell)
	var nearby := neighbors.filter(func(next: Vector2i) -> bool:
		return absi(next.x - origin.x) + absi(next.y - origin.y) <= radius)
	if not _is_foodless():
		var approach: float = global_position.distance_to(route_service.cell_to_world(cell)) * route_service.entry_cost(cell) / speed
		nearby = nearby.filter(func(next: Vector2i) -> bool:
			var step_energy: float = planner.travel_energy(route_service.entry_cost(next), speed)
			return needs.can_afford(approach + step_energy + planner.escape_energy(next, speed) + 2.0))
		if nearby.is_empty() and not neighbors.is_empty():
			_seek_food()
			return
	if nearby.is_empty():
		_set_status(Status.WANDERING)
		_timer = 1.0
	else:
		_walk(route_service.make_route([cell, nearby.pick_random()]), &"wander")

func _can_recover() -> bool:
	if not needs.can_afford(planner.escape_energy(route_service.world_to_cell(global_position), speed)):
		return false
	refresh_meal_reservation()
	return _meal != null and _meal.active

func _seek_food() -> void:
	if combat != null and role == Role.WARRIOR:
		combat.seek_meal()
		return
	if cargo.is_empty() and not (construction != null and construction.has_cargo()) and _is_foodless() and is_instance_valid(home):
		_decide()
		return
	_waiting_for_work = false
	_set_waiting_reason(WorkPlan.WaitReason.NONE)
	_release_work()
	if _meal == null or not _meal.active:
		_meal = planner.reserve_meal()
	if _meal == null:
		_set_status(Status.WAITING_FOR_FOOD)
		_timer = 1.0
		return
	var route: Route = planner.food_route(route_service.world_to_cell(global_position))
	if not route.is_valid():
		_set_status(Status.WAITING_FOR_FOOD)
		_timer = 1.0
		return
	_walk(route, &"food")

func _go_home() -> void:
	if not is_instance_valid(home):
		_seek_food()
		return
	var entry: Vector2i = planner.accessible_entry(home)
	var route: Route = planner.home_route(home, route_service.world_to_cell(global_position))
	if not route.is_valid() or not needs.can_afford(planner.travel_energy(route.cost, speed * TripPlanner.CARRY_SPEED_RATIO) + planner.escape_energy(entry, speed)):
		_seek_food()
		return
	_walk(route, &"home")

func _walk(route: Route, destination: StringName) -> void:
	_destination = destination
	motion.follow(route, global_position)
	_set_status(Status.WALKING)

func _arrive() -> void:
	if _destination == &"flee":
		_set_status(Status.WANDERING)
		_timer = 0.2
		return
	if _destination in [&"combat_chase", &"combat_tower", &"combat_meal", &"combat_patrol"]:
		combat.arrive(_destination)
		return
	if _destination in [&"site_pickup", &"site_delivery", &"site_assembly"]:
		construction.arrive(_destination)
		return
	match _destination:
		&"work":
			var cell: Vector2i = route_service.world_to_cell(global_position)
			if not is_instance_valid(current_workplace) or (not _plan.foodless and not planner.can_finish_work(cell, needs, speed, work_time)) or not current_workplace.begin_work(self):
				_seek_food()
				return
			_set_status(Status.WORKING)
			_timer = work_time
		&"delivery":
			_unload()
		&"pickup":
			_load_pickup()
		&"wander":
			_set_status(Status.WANDERING)
			_timer = randf_range(0.2, 0.7)
		&"food":
			_set_status(Status.EATING)
			_timer = AntNeeds.MEAL_SECONDS
		&"home":
			_carrying = false
			_set_status(Status.HOME)
			_timer = 0.5

func _on_navigation_changed() -> void:
	_queue_reconsideration(true)

func _on_food_sources_changed() -> void:
	if status == Status.WALKING and _destination == &"food" or status == Status.EATING:
		_seek_food()
	else:
		_on_navigation_changed()

func _on_work_opportunities_changed() -> void:
	if status == Status.WANDERING or (status == Status.HOME and _waiting_for_work):
		_timer = 0.0
	elif status == Status.WALKING and _destination == &"work":
		_queue_reconsideration(false)

func _queue_reconsideration(navigation_changed: bool) -> void:
	_navigation_pending = _navigation_pending or navigation_changed
	if not _reconsider_queued:
		_reconsider_queued = true
		_reconsider_route.call_deferred()

func _reconsider_route() -> void:
	# Registry and navigation notifications can arrive inside one build command.
	# Wait for its commit and combine the notifications into one decision.
	var geometry_changed: bool = _navigation_pending
	_navigation_pending = false
	_reconsider_queued = false
	if status == Status.DEAD:
		return
	var cell: Vector2i = route_service.world_to_cell(global_position)
	if combat != null and role == Role.WARRIOR:
		combat.navigation_changed()
		return
	if construction != null and construction.job != null:
		if geometry_changed and status != Status.EATING:
			if not construction.resume():
				construction.release()
				_decide()
		return
	if status == Status.WORKING:
		if geometry_changed and _plan != null:
			if _plan.foodless:
				if _can_recover():
					_seek_food()
			elif _is_foodless():
				_plan.foodless = true
				planner.inventory.release(_meal)
				_meal = null
			elif not planner.can_finish_work(cell, needs, speed, _timer):
				_seek_food()
	elif status == Status.WALKING:
		if _destination == &"work":
			_decide()
		elif geometry_changed and _destination == &"home":
			_go_home()
		elif geometry_changed and _destination == &"food":
			_seek_food()
		elif geometry_changed and _destination in [&"wander", &"pickup"]:
			_decide()
		elif geometry_changed and _destination == &"delivery":
			_deliver()

func workplace_removed(workplace: Workplace) -> void:
	if current_workplace == workplace:
		_release_work()
		_go_home()

func _release_work() -> void:
	if is_instance_valid(current_workplace):
		current_workplace.release_worker(self)
	current_workplace = null

func _set_waiting_reason(reason: WorkPlan.WaitReason) -> void:
	if _waiting_reason != reason:
		_waiting_reason = reason
		waiting_changed.emit()

func _set_status(value: Status) -> void:
	if status != value:
		status = value
		status_changed.emit(status)

func take_damage(amount: int, cause: DeathCause = DeathCause.ENEMY) -> void:
	if status == Status.DEAD or amount <= 0: return
	health = maxi(0, health - amount)
	queue_redraw()
	if health == 0: die(cause)

## Removes the unit from the game. No further consequences.
func die(cause: DeathCause = DeathCause.OTHER) -> void:
	if status == Status.DEAD:
		return
	_set_status(Status.DEAD)
	if combat != null: combat.leave_tower()
	if construction != null: construction.release()
	_release_work()
	_discard_cargo()
	planner.inventory.release(_meal)
	if is_instance_valid(home):
		home.remove_resident(self)
	died.emit(self, cause)
	queue_free()

func debug_snapshot() -> Dictionary:
	return {"role": Role.keys()[role], "status": Status.keys()[status], "satiety": needs.satiety, "destination": _destination, "route_cells": motion.route.cells.size() if motion.route != null else 0}

func _draw() -> void:
	# Pixel-native ant art remains crisp at every integer camera zoom.
	var sprite := get_node_or_null("Sprite") as Node2D
	if sprite != null:
		sprite.visible = status not in [Status.HOME, Status.DEAD]
		sprite.rotation = _last_direction.angle() + PI * 0.5
	if status == Status.HOME or status == Status.DEAD:
		return
	var forward: Vector2 = _last_direction
	var side := Vector2(-forward.y, forward.x)
	if sprite == null:
		var leg_phase: float = sin(_animation_time * 22.0) if status == Status.WALKING else 0.0
		for pair in range(3):
			var origin: Vector2 = forward * (pair - 1) * 2.0
			for sign_value in [-1.0, 1.0]:
				var foot: Vector2 = origin + side * sign_value * 3.5 + forward * leg_phase * sign_value
				draw_line(origin, foot.round(), Color("222521"), 1.0)
		var abdomen := Color("a87054") if role == Role.WARRIOR else (Color("50677b") if role == Role.CARRIER else Color("38271e"))
		draw_circle(-forward * 3.0, 2.0, abdomen)
		draw_circle(Vector2.ZERO, 1.5, Color("241e19"))
		draw_circle(forward * 3.0, 1.7, Color("33251d"))
		for sign_value in [-1.0, 1.0]:
			draw_line(forward * 4.0, (forward * 6.0 + side * sign_value * 2.0).round(), Color("241e19"), 1.0)
	if _carrying:
		draw_rect(Rect2(Vector2(-1, -6), Vector2(3, 3)), Color("d7bc73"))
	if health < max_health:
		draw_rect(Rect2(-4, -10, 8, 1), Color("38271e"))
		draw_rect(Rect2(-4, -10, 8.0 * health / max_health, 1), Color("e58b76"))
	if needs.fraction() < 0.25:
		draw_rect(Rect2(-4, -8, 8, 1), Color("38271e"))
		draw_rect(Rect2(-4, -8, 8 * needs.fraction(), 1), Color("edb86c"))
