class_name AntAgent
extends Node2D

const TIMING := preload("res://game/navigation/navigation_timing.gd")
## Executes plans; needs, route execution, and assignment policy are separate objects.

enum Role { WORKER, CARRIER, WARRIOR }
enum DeathCause { STARVATION, DEMOLISHED, OTHER, PLAYER, ENEMY, TRAP }
enum Status { HOME, WALKING, WORKING, EATING, WAITING_FOR_FOOD, DEAD, WANDERING, CONSTRUCTING, GUARDING, FIGHTING }
signal work_completed(human: Node2D, workplace: Node2D)
signal died(human: Node2D, cause: DeathCause)
signal status_changed(status: Status)
signal cell_changed(old: Vector2i, next: Vector2i)
signal waiting_changed

const DEFAULT_PROFILE: AntProfile = preload("res://game/ants/worker.tres")

@export var profile: AntProfile
var story_id: StringName
var speed: float = DEFAULT_PROFILE.speed
var work_time: float = DEFAULT_PROFILE.work_seconds
var carry_capacity: int = DEFAULT_PROFILE.carry_capacity
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
var work := AntWork.new()
var transport := AntTransport.new()
var _meal: StockReservation
var _destination: StringName = &"home"
var _timer := 0.0
var departure_delay := 0.0
@onready var _visual: AntVisual = get_node_or_null("Visual") as AntVisual
var _animation_time := 0.0
var _last_direction := Vector2.UP
var _waiting_reason: WorkPlan.WaitReason = WorkPlan.WaitReason.NONE
var waiting_reason: WorkPlan.WaitReason:
	get: return _waiting_reason
var _reconsider_queued := false
var _navigation_pending := false

func apply_profile() -> void:
	var definition: AntProfile = profile if profile != null else DEFAULT_PROFILE
	needs.configure(definition.satiety_capacity)
	speed = definition.speed
	work_time = definition.work_seconds
	carry_capacity = definition.carry_capacity
	max_health = definition.health
	health = max_health
	attack_damage = definition.damage

func meal_fraction() -> float:
	return (profile if profile != null else DEFAULT_PROFILE).meal_fraction

func configure(nest: House, policy: TripPlanner, navigation: RouteService, storage: ColonyLogistics) -> void:
	home = nest
	work.ant = self
	transport.ant = self
	planner = policy
	needs.rules = policy.satiety_rules
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
	_refresh_visual()

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
	work.release()
	if planner != null and is_instance_valid(planner.inventory):
		transport.discard()
		planner.inventory.release(_meal)
	if is_instance_valid(home):
		home.remove_resident(self)

func _physics_process(delta: float) -> void:
	if status == Status.DEAD:
		return
	var rate: float = needs.rules.rest_rate
	if status == Status.WALKING:
		rate = needs.rules.walk_rate
	elif status in [Status.WORKING, Status.CONSTRUCTING]:
		rate = needs.rules.work_rate
	elif status == Status.EATING:
		rate = needs.rules.eat_rate
	needs.consume(delta, rate)
	_animation_time += delta
	if needs.satiety <= 0.0:
		die(DeathCause.STARVATION)
		return
	if combat != null and combat.physics(delta):
		_refresh_visual()
		return
	match status:
		Status.HOME:
			_timer -= delta
			if _timer <= 0.0:
				_decide()
		Status.WALKING:
			var before: Vector2 = global_position
			global_position = motion.step(global_position, movement_speed(), delta)
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
			if not work.tick(delta):
				return
		Status.CONSTRUCTING:
			construction.tick(delta)
		Status.EATING:
			_timer -= delta
			if _timer <= 0.0:
				_finish_meal()
				_meal = null
				if role == Role.WARRIOR:
					_set_status(Status.HOME)
					_timer = 0.3
				elif transport.cargo.is_empty() and not (construction != null and construction.has_cargo()):
					transport.carrying = false
					_go_home()
				else:
					resume_delivery()
		Status.WANDERING:
			_timer -= delta
			if _timer <= 0.0:
				_decide()
		Status.WAITING_FOR_FOOD:
			_timer -= delta
			if _timer <= 0.0:
				_decide()
	_refresh_visual()

func _decide() -> void:
	if not TIMING.enabled:
		_decide_inner()
		return
	TIMING.begin(&"ant_decide")
	_decide_inner()
	TIMING.end()

func _decide_inner() -> void:
	if combat != null and role == Role.WARRIOR:
		combat.decide()
		return
	if construction != null and construction.has_cargo():
		resume_delivery()
		return
	if not transport.cargo.is_empty():
		resume_delivery()
		return
	var foodless: bool = _is_foodless()
	refresh_meal_reservation()
	if construction != null and status in [Status.HOME, Status.WAITING_FOR_FOOD, Status.WANDERING] and construction.decide(): return
	if role == Role.CARRIER:
		transport.decide_pickup(foodless)
		return
	work.decide(foodless)

## Construction carries reserved materials; transport delivers normal stock.
func resume_delivery() -> void:
	if construction != null and construction.has_cargo():
		if not construction.resume():
			_set_status(Status.WAITING_FOR_FOOD)
			_timer = 1.0
		return
	transport.deliver()

func _wander() -> void:
	var cell: Vector2i = route_service.world_to_cell(global_position)
	var origin: Vector2i = planner.accessible_entry(home) if is_instance_valid(home) else cell
	var radius: int = maxi(2, absi(cell.x - origin.x) + absi(cell.y - origin.y))
	var neighbors: Array[Vector2i] = route_service.snapshot().neighbors(cell)
	var nearby := neighbors.filter(func(next: Vector2i) -> bool:
		return absi(next.x - origin.x) + absi(next.y - origin.y) <= radius)
	if not _is_foodless():
		var approach := planner.approach_energy(global_position, cell, speed)
		nearby = nearby.filter(func(next: Vector2i) -> bool:
			var step_energy: float = planner.travel_energy(route_service.entry_cost(next), speed)
			return needs.can_afford(approach + step_energy + planner.escape_energy(next, speed) + needs.rules.travel_reserve))
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

func _finish_meal() -> void:
	var cell := route_service.world_to_cell(global_position)
	var meal_site: Building = home if _destination == &"combat_meal" else planner.canteen_at_entry(cell)
	var ticket := _meal
	if planner.inventory.consume(ticket, meal_site as Canteen):
		needs.eat()
		if is_instance_valid(meal_site):
			meal_site.show_stock_change(ticket.type, -ticket.amount)

func _seek_food() -> void:
	if combat != null and role == Role.WARRIOR:
		combat.seek_meal()
		return
	if transport.cargo.is_empty() and not (construction != null and construction.has_cargo()) and _is_foodless() and is_instance_valid(home):
		_decide()
		return
	work.waiting_for_work = false
	_set_waiting_reason(WorkPlan.WaitReason.NONE)
	work.release()
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
	if not route.is_valid() or not needs.can_afford(planner.travel_energy(route.cost, movement_speed()) + planner.escape_energy(entry, speed)):
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
			work.arrive()
		&"delivery":
			transport.unload()
		&"pickup":
			transport.load_pickup()
		&"wander":
			_set_status(Status.WANDERING)
			_timer = randf_range(0.2, 0.7)
		&"food":
			_set_status(Status.EATING)
			_timer = needs.rules.meal_seconds
		&"home":
			transport.carrying = false
			_set_status(Status.HOME)
			_timer = 0.5

func movement_speed() -> float:
	return speed * (planner.carry_speed_ratio if transport.carrying else 1.0)

func step_clear_of_construction(cell: Vector2i) -> void:
	var previous := route_service.world_to_cell(global_position)
	global_position = route_service.cell_to_world(cell)
	_queue_reconsideration(true)
	cell_changed.emit(previous, cell)

func _on_navigation_changed() -> void:
	if not route_service.last_change_only_cheaper:
		_queue_reconsideration(true)

func _on_food_sources_changed() -> void:
	if status == Status.WALKING and _destination == &"food" or status == Status.EATING:
		_seek_food()
	else:
		_queue_reconsideration(true)

func _on_work_opportunities_changed() -> void:
	if status == Status.WANDERING or (status == Status.HOME and work.waiting_for_work):
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
		if geometry_changed:
			work.reconsider()
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
			resume_delivery()

func workplace_removed(workplace: Workplace) -> void:
	if work.workplace == workplace:
		work.release()
		_go_home()

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
	_refresh_visual()
	if health == 0: die(cause)

## Removes the unit from the game. No further consequences.
func die(cause: DeathCause = DeathCause.OTHER) -> void:
	if status == Status.DEAD:
		return
	_set_status(Status.DEAD)
	if combat != null: combat.leave_tower()
	if construction != null: construction.release()
	work.release()
	transport.discard()
	planner.inventory.release(_meal)
	if is_instance_valid(home):
		home.remove_resident(self)
	died.emit(self, cause)
	queue_free()

func debug_snapshot() -> Dictionary:
	return {"role": Role.keys()[role], "status": Status.keys()[status], "satiety": needs.satiety, "destination": _destination, "route_cells": motion.route.cells.size() if motion.route != null else 0}

func authored_sprite() -> Node2D:
	return get_node_or_null("Sprite") as Node2D

func _refresh_visual() -> void:
	if _visual != null:
		_visual.update_pose(self, _last_direction, _animation_time, transport.carrying)

## Preserve the version 1 snapshot fields. Scene references are stored as indices.
func capture_state(buildings: Array[Building], sites: Array[ConstructionSite]) -> Dictionary:
	var state := {
		"role": role, "position": position, "speed": speed,
		"work_time": work_time, "carry_capacity": carry_capacity, "max_health": max_health,
		"health": health, "attack_damage": attack_damage, "status": status,
		"_destination": _destination, "_timer": _timer, "_last_direction": _last_direction,
		"_waiting_reason": _waiting_reason,
	}
	state["home"] = buildings.find(home)
	state["story_id"] = str(story_id)
	state["satiety"] = needs.satiety
	state["capacity"] = needs.capacity
	state["meal"] = _meal != null and _meal.active
	work.capture_state(state, buildings)
	transport.capture_state(state, buildings)
	if motion.route != null:
		state["route"] = motion.route.cells.duplicate()
		state["route_index"] = motion.route.current_index
		state["finished"] = motion.finished
	if construction != null and construction.job != null:
		var job: ConstructionJob = construction.job
		state["job"] = {"site": sites.find(job.site), "source": buildings.find(job.source), "materials": ResourceAmount.pack(job.materials), "picked_up": job.picked_up, "assembly": job.assembly}
	if combat != null:
		state["tower"] = buildings.find(combat.tower)
		state["combat_attack"] = combat.attack_cooldown()
	return state

func restore_state(state: Dictionary, buildings: Array[Building], sites: Array[ConstructionSite]) -> void:
	story_id = StringName(state.get("story_id", ""))
	planner.inventory.release(_meal)
	_meal = planner.inventory.reserve(planner.food_type, 1, true) if state.meal else null
	needs.capacity = state.capacity
	needs.satiety = state.satiety
	transport.restore_state(state, buildings)
	work.restore_state(state, buildings)
	if state.has("route"):
		var cells: Array[Vector2i] = []
		cells.assign(state.route)
		motion.route = route_service.make_route(cells)
		motion.route.current_index = state.route_index
		motion.finished = state.finished
	if state.has("job"):
		var job := ConstructionJob.new()
		job.site = sites[state.job.site] if state.job.site >= 0 else null
		job.source = buildings[state.job.source] as House if state.job.source >= 0 else null
		job.materials = ResourceAmount.unpack(state.job.materials, planner.inventory.type_by_id)
		job.picked_up = state.job.picked_up
		job.assembly = state.job.assembly
		construction.job = job
		if job.assembly and job.live(): job.site.builder = self
	if combat != null:
		var occupied_tower: DefenseBuilding
		if state.get("tower", -1) >= 0:
			occupied_tower = buildings[state.tower] as DefenseBuilding
		combat.restore_state(state.get("combat_attack", 0.0), occupied_tower)
	position = state.position
	speed = state.speed
	work_time = state.work_time
	carry_capacity = state.carry_capacity
	max_health = state.max_health
	health = state.health
	attack_damage = state.attack_damage
	status = state.status
	_destination = state._destination
	_timer = state._timer
	_last_direction = state._last_direction
	_waiting_reason = state._waiting_reason
	_refresh_visual()
