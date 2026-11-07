class_name AntAgent
extends Node2D
## Executes plans; needs, route execution, and assignment policy are separate objects.

enum Role { WORKER, CARRIER }
enum DeathCause { STARVATION, DEMOLISHED, OTHER, PLAYER }
enum Status { HOME, WALKING, WORKING, EATING, WAITING_FOR_FOOD, DEAD, WANDERING }
signal work_completed(human: Node2D, workplace: Node2D)
signal died(human: Node2D, cause: DeathCause)
signal status_changed(status: Status)
signal cell_changed(old: Vector2i, next: Vector2i)
signal waiting_changed

@export var speed := 24.0
@export var work_time := 3.0
@export_range(1, 100) var carry_capacity := 2
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
var _main_delivery := false
var _delivery_nest: House
var _pickup_source: Building
var _angle := 0.0
var _animation_time := 0.0
var _last_direction := Vector2.UP
var _waiting_for_work := false
var _waiting_reason: WorkPlan.WaitReason = WorkPlan.WaitReason.NONE
var waiting_reason: WorkPlan.WaitReason:
	get: return _waiting_reason
var _reconsider_queued := false
var _navigation_pending := false

func configure(nest: House, policy: TripPlanner, navigation: RouteService, storage: ColonyLogistics) -> void:
	home = nest
	planner = policy
	route_service = navigation
	motion.navigation = navigation
	logistics = storage

func _ready() -> void:
	assert(home != null and planner != null and route_service != null, "Ant dependencies must be configured before entering the tree")
	var sprite: Node = get_node_or_null("Sprite")
	if sprite != null:
		sprite.queue_free()
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
	return not planner.food_within_range(route_service.world_to_cell(global_position), speed)

func _exit_tree() -> void:
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
	elif status == Status.WORKING:
		rate = AntNeeds.WORK_RATE
	elif status == Status.EATING:
		rate = AntNeeds.EAT_RATE
	needs.consume(delta, rate)
	_animation_time += delta
	if needs.satiety <= 0.0:
		die(DeathCause.STARVATION)
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
		Status.EATING:
			_timer -= delta
			if _timer <= 0.0:
				if planner.inventory.consume(_meal):
					needs.eat()
				_meal = null
				if cargo.is_empty():
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
				if cargo.is_empty():
					_seek_food()
				else:
					_deliver()
	queue_redraw()

func _decide() -> void:
	if not cargo.is_empty():
		_deliver()
		return
	var foodless: bool = _is_foodless()
	refresh_meal_reservation()
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
	var dispatch: Dictionary = logistics.nearest_dispatch(cell, _can_collect_shipment)
	if not dispatch.is_empty():
		_pickup_source = dispatch.source
		_walk(dispatch.route, &"pickup")
		return
	_pickup_source = null
	if foodless:
		_wander()
	elif not needs.can_afford(planner.escape_energy(cell, speed) + 2.0):
		_seek_food()
	elif is_instance_valid(home) and (cell - planner.accessible_entry(home)).length_squared() > 4:
		_go_home()
	else:
		_wander()

func _can_collect_shipment(pickup: Route) -> bool:
	var cell: Vector2i = pickup.cells.back()
	return _can_start_pickup(pickup, logistics.route_to(logistics.closest_base(cell, carry_capacity), cell))

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
	var source: Building = _pickup_source
	_pickup_source = null
	if is_instance_valid(source) and source.is_inside_tree():
		if source is House and logistics.ready_to_dispatch(source):
			var cell: Vector2i = route_service.world_to_cell(global_position)
			var delivery: Route = logistics.route_to(logistics.closest_base(cell, carry_capacity), cell)
			if delivery.is_valid() and _can_deliver(delivery, cell):
				cargo = planner.inventory.dispatch(source, carry_capacity)
				_shipment = not cargo.is_empty()
				_main_delivery = _shipment
	if cargo.is_empty():
		# Stock may have changed while this carrier was en route.
		_decide()
	else:
		_deliver()

func _deliver() -> void:
	_carrying = true
	var cell: Vector2i = route_service.world_to_cell(global_position)
	var count: int = WorldInventory.cargo_size(cargo)
	_delivery_nest = logistics.closest_base(cell, count) if _main_delivery else logistics.closest_depot(cell, count)
	var route: Route = logistics.route_to(_delivery_nest, cell)
	if route.is_valid() and _can_deliver(route, cell):
		_walk(route, &"delivery")
		return
	var meal_energy: float = planner.escape_energy(cell, speed * TripPlanner.CARRY_SPEED_RATIO)
	var meal_would_enable_delivery: bool = route.is_valid() and _delivery_energy(route, cell) + AntNeeds.SAFETY_MARGIN <= AntNeeds.CAPACITY
	var meal_due: bool = meal_would_enable_delivery or needs.satiety <= meal_energy + AntNeeds.SAFETY_MARGIN + 2.0
	if meal_due and needs.satiety > meal_energy and not _is_foodless():
		_seek_food()
	else:
		_set_status(Status.WAITING_FOR_FOOD)
		_timer = 1.0

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

func _unload() -> void:
	if _shipment and logistics.owns(_delivery_nest) and _delivery_nest.is_main_nest:
		planner.inventory.close_shipment(cargo, true, null if _delivery_nest == logistics.main_nest else _delivery_nest)
	elif _shipment or not logistics.deposit(_delivery_nest, cargo):
		_main_delivery = true
		_deliver()
		return
	_clear_cargo()
	_go_home()

func _clear_cargo() -> void:
	cargo.clear()
	_shipment = false
	_main_delivery = false
	_delivery_nest = null
	_carrying = false

func _discard_cargo() -> void:
	if _shipment:
		planner.inventory.close_shipment(cargo, false)
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
	if cargo.is_empty() and _is_foodless() and is_instance_valid(home):
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
	motion.follow(route)
	_set_status(Status.WALKING)

func _arrive() -> void:
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

## Removes the unit from the game. No further consequences.
func die(cause: DeathCause = DeathCause.OTHER) -> void:
	if status == Status.DEAD:
		return
	_set_status(Status.DEAD)
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
	if status == Status.HOME or status == Status.DEAD:
		return
	var forward: Vector2 = _last_direction
	var side := Vector2(-forward.y, forward.x)
	var leg_phase: float = sin(_animation_time * 22.0) if status == Status.WALKING else 0.0
	for pair in range(3):
		var origin: Vector2 = forward * (pair - 1) * 2.0
		for sign_value in [-1.0, 1.0]:
			var foot: Vector2 = origin + side * sign_value * 3.5 + forward * leg_phase * sign_value
			draw_line(origin, foot.round(), Color("222521"), 1.0)
	var abdomen := Color("50677b") if role == Role.CARRIER else Color("38271e")
	draw_circle(-forward * 3.0, 2.0, abdomen)
	draw_circle(Vector2.ZERO, 1.5, Color("241e19"))
	draw_circle(forward * 3.0, 1.7, Color("33251d"))
	for sign_value in [-1.0, 1.0]:
		draw_line(forward * 4.0, (forward * 6.0 + side * sign_value * 2.0).round(), Color("241e19"), 1.0)
	if _carrying:
		draw_rect(Rect2(Vector2(-1, -6), Vector2(3, 3)), Color("d7bc73"))
	if needs.satiety < 30.0:
		draw_rect(Rect2(-4, -8, 8, 1), Color("38271e"))
		draw_rect(Rect2(-4, -8, 8 * needs.satiety / AntNeeds.CAPACITY, 1), Color("edb86c"))
