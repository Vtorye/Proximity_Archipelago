class_name AntAgent
extends Node2D
## Executes plans; needs, route execution, and assignment policy are separate objects.

enum DeathCause { STARVATION, DEMOLISHED, OTHER }
enum Status { HOME, WALKING, WORKING, EATING, WAITING_FOR_FOOD, DEAD }
signal work_completed(human: Node2D, workplace: Node2D)
signal died(human: Node2D, cause: DeathCause)
signal status_changed(status: Status)
signal cell_changed(old: Vector2i, next: Vector2i)

@export var speed := 24.0
@export var work_time := 3.0
var home: House
var planner: TripPlanner
var route_service: RouteService
var needs := AntNeeds.new()
var motion := AntMotion.new()
var status: Status = Status.HOME
var current_workplace: Workplace
var _plan: WorkPlan
var _meal: StockReservation
var _destination: StringName = &"home"
var _timer := 0.0
var _carrying := false
var _angle := 0.0
var _animation_time := 0.0
var _last_direction := Vector2.UP

func configure(nest: House, policy: TripPlanner, navigation: RouteService) -> void:
	home = nest
	planner = policy
	route_service = navigation
	motion.navigation = navigation

func _ready() -> void:
	assert(home != null and planner != null and route_service != null, "Ant dependencies must be configured before entering the tree")
	var sprite: Node = get_node_or_null("Sprite")
	if sprite != null:
		sprite.queue_free()
	route_service.navigation_changed.connect(_on_navigation_changed)
	route_service.food_sources_changed.connect(_on_food_sources_changed)
	_timer = randf_range(0.3, 1.4)
	_meal = planner.reserve_meal()

func _exit_tree() -> void:
	_release_work()
	if planner != null and is_instance_valid(planner.inventory):
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
				current_workplace.complete_cycle(self)
				work_completed.emit(self, current_workplace)
				_release_work()
				_carrying = true
				_go_home()
		Status.EATING:
			_timer -= delta
			if _timer <= 0.0:
				if planner.inventory.consume(_meal):
					needs.eat()
				_meal = null
				_carrying = false
				_go_home()
		Status.WAITING_FOR_FOOD:
			_timer -= delta
			if _timer <= 0.0:
				_seek_food()
	queue_redraw()

func _decide() -> void:
	if _meal == null or not _meal.active:
		_meal = planner.reserve_meal()
	_plan = planner.plan_work(self, home, needs, speed, work_time, _meal)
	if _plan != null:
		current_workplace = _plan.workplace
		_walk(_plan.outward, &"work")
	else:
		_seek_food()

func _seek_food() -> void:
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
			if not is_instance_valid(current_workplace) or not planner.can_finish_work(cell, needs, speed, work_time):
				_seek_food()
				return
			_set_status(Status.WORKING)
			_timer = work_time
		&"food":
			_set_status(Status.EATING)
			_timer = AntNeeds.MEAL_SECONDS
		&"home":
			_carrying = false
			_set_status(Status.HOME)
			_timer = 0.5

func _on_navigation_changed() -> void:
	if status == Status.WORKING:
		if not planner.can_finish_work(route_service.world_to_cell(global_position), needs, speed, _timer):
			_seek_food()
	elif status == Status.WALKING:
		var escape: float = planner.escape_energy(route_service.world_to_cell(global_position), speed)
		if route_service.route_affected(motion.route) or not needs.can_afford(escape + 3.0):
			_seek_food()

func _on_food_sources_changed() -> void:
	if status == Status.WALKING and _destination == &"food" or status == Status.EATING:
		_seek_food()
	else:
		_on_navigation_changed()

func _release_work() -> void:
	if is_instance_valid(current_workplace):
		current_workplace.release_worker(self)
	current_workplace = null

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
	planner.inventory.release(_meal)
	if is_instance_valid(home):
		home.remove_resident(self)
	died.emit(self, cause)
	queue_free()

func debug_snapshot() -> Dictionary:
	return {"status": Status.keys()[status], "satiety": needs.satiety, "destination": _destination, "route_cells": motion.route.cells.size() if motion.route != null else 0}

func _draw() -> void:
	# Pixel-native ant art remains crisp at every integer camera zoom.
	var forward: Vector2 = _last_direction
	var side := Vector2(-forward.y, forward.x)
	var leg_phase: float = sin(_animation_time * 22.0) if status == Status.WALKING else 0.0
	for pair in range(3):
		var origin: Vector2 = forward * (pair - 1) * 2.0
		for sign_value in [-1.0, 1.0]:
			var foot: Vector2 = origin + side * sign_value * 3.5 + forward * leg_phase * sign_value
			draw_line(origin, foot.round(), Color("222521"), 1.0)
	draw_circle(-forward * 3.0, 2.0, Color("38271e"))
	draw_circle(Vector2.ZERO, 1.5, Color("241e19"))
	draw_circle(forward * 3.0, 1.7, Color("33251d"))
	for sign_value in [-1.0, 1.0]:
		draw_line(forward * 4.0, (forward * 6.0 + side * sign_value * 2.0).round(), Color("241e19"), 1.0)
	if _carrying:
		draw_rect(Rect2(Vector2(-1, -6), Vector2(3, 3)), Color("d7bc73"))
	if needs.satiety < 30.0:
		draw_rect(Rect2(-4, -8, 8, 1), Color("38271e"))
		draw_rect(Rect2(-4, -8, 8 * needs.satiety / AntNeeds.CAPACITY, 1), Color("edb86c"))
