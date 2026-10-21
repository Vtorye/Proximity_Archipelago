extends Node2D

const UNIT_SIZE: int = 16

signal work_completed(human: Node2D, workplace: Node2D)
signal died(human: Node2D)

enum Status { HOME, WALKING, WORKING, EATING, WAITING_FOR_FOOD, DEAD }

@export var speed: float = 16.0
@export var work_time: float = 3.0
@export var eat_time_range: Vector2 = Vector2(2.0, 4.0)
@export var home_think_time_range: Vector2 = Vector2(1.0, 3.0)
@export var starting_food: int = 3
@export var eat_bonus: int = 3
@export var food_wait_limit: float = 10.0

@export var home: Node2D

var food_left: int
var status: Status = Status.HOME
var current_workplace: Workplace
var current_canteen: Canteen
var _destination: Building # maybe remove current_canteen and current_workplace and just check if _destination if on needed class...? but ok, ok, ok this approach is good as well 
var _path: PackedVector2Array = PackedVector2Array()
var _path_index := 0
var _timer := 0.0
var _site_offset := Vector2.ZERO


func _ready() -> void:
	add_to_group("humans")
	HumanNavigation.navigation_changed.connect(_on_navigation_changed)
	assert(is_instance_valid(home), "Human " + str(name) + " has no home")
	food_left = randi_range(1, maxi(1, starting_food))
	# global_position = home.global_position
	_schedule_home_thinking()


func _physics_process(delta: float) -> void:
	match status:
		Status.HOME:
			_timer -= delta
			if _timer <= 0.0:
				if food_left <= 0:
					_seek_canteen()
				else:
					_seek_workplace()
		Status.WALKING:
			animate_walking(delta)
			_move_along_path(delta)
		Status.WORKING:
			_timer -= delta
			animate_working(delta)
			if _timer <= 0.0:
				food_left -= 1
				if is_instance_valid(current_workplace):
					current_workplace.work_complete(self)
				work_completed.emit(self, current_workplace)
				if is_instance_valid(current_workplace):
					current_workplace.release_worker(self)
				current_workplace = null
				_go_home()
		Status.EATING:
			_timer -= delta
			animate_eating(delta)
			if _timer <= 0.0:
				if is_instance_valid(current_canteen) and current_canteen.has_food():
					current_canteen.try_consume_food(1)
					food_left += eat_bonus
					current_canteen = null
					_go_home()
				else:
					status = Status.WAITING_FOR_FOOD
					_timer = food_wait_limit
		Status.WAITING_FOR_FOOD:
			animate_eating(delta)
			_timer -= delta
			if is_instance_valid(current_canteen) and current_canteen.has_food():
				status = Status.EATING
				_timer = _random_range(eat_time_range)
			elif _timer <= 0.0:
				_die()


func _seek_workplace() -> void:
	var best: Workplace
	var best_cost := INF
	for candidate in get_tree().get_nodes_in_group("workplaces"):
		if not candidate is Workplace or not candidate.has_free_slot():
			continue
		var cost := HumanNavigation.get_path_cost(global_position, candidate.global_position)
		if cost < best_cost:
			best_cost = cost
			best = candidate
	if best == null:
		_schedule_home_thinking()
		return
	if not best.reserve_worker(self):
		_timer = 0.1
		return
	current_workplace = best
	_site_offset = _random_site_offset()
	_travel_to(best)


func _seek_canteen() -> void:
	var best: Canteen
	var best_cost := INF
	for candidate in get_tree().get_nodes_in_group("canteens"):
		if not candidate is Canteen:
			continue
		var cost := HumanNavigation.get_path_cost(global_position, candidate.global_position)
		if cost < best_cost:
			best_cost = cost
			best = candidate
	if best == null:
		status = Status.WAITING_FOR_FOOD
		_timer = food_wait_limit
		return
	current_canteen = best
	_site_offset = _random_site_offset()
	_travel_to(best)


func _go_home() -> void:
	if is_instance_valid(home):
		_site_offset = _random_site_offset()
		_travel_to(home)


func _travel_to(destination: Node2D) -> void:
	_destination = destination
	_path = HumanNavigation.get_path_world_positions(global_position, destination.global_position)
	_path_index = 0
	if _path.is_empty():
		if destination == current_workplace and is_instance_valid(current_workplace):
			current_workplace.release_worker(self)
			current_workplace = null
		_destination = null
		status = Status.HOME
		if destination == home:
			_schedule_home_thinking()
		return
	status = Status.WALKING


func _on_navigation_changed() -> void:
	if status == Status.WALKING and is_instance_valid(_destination):
		_travel_to(_destination)


func _move_along_path(delta: float) -> void:
	if _path_index < _path.size():
		var waypoint := _path[_path_index]
		if global_position.distance_to(waypoint) <= 1.5:
			_path_index += 1
			return
		global_position = global_position.move_toward(waypoint, speed * delta)
		return
	if not is_instance_valid(_destination):
		status = Status.HOME
		_schedule_home_thinking()
		return
	var arrival_position := _destination.global_position + _site_offset
	if global_position.distance_to(arrival_position) > 1.5:
		global_position = global_position.move_toward(arrival_position, speed * delta)
		return
	_arrive()


func _arrive() -> void:
	if _destination == home:
		_destination = null
		status = Status.HOME
		_site_offset = Vector2.ZERO
		_schedule_home_thinking()
	elif _destination == current_workplace:
		_destination = null
		status = Status.WORKING
		_timer = work_time
		animate_working(0.0)
	elif _destination == current_canteen:
		_destination = null
		status = Status.EATING
		_timer = _random_range(eat_time_range)
		animate_eating(0.0)
	else:
		status = Status.HOME
		_schedule_home_thinking()


func _die() -> void:
	if is_instance_valid(current_workplace):
		current_workplace.release_worker(self)
	status = Status.DEAD
	animate_dying()
	died.emit(self)
	queue_free()


func _schedule_home_thinking() -> void:
	_timer = _random_range(home_think_time_range)
	animate_at_home()


func _random_range(bounds: Vector2) -> float:
	return randf_range(minf(bounds.x, bounds.y), maxf(bounds.x, bounds.y))


func _random_site_offset() -> Vector2:
	return Vector2(randf_range(-1.0, 1.0) * UNIT_SIZE / 2, randf_range(-1.0, 1.0) * UNIT_SIZE / 2)


## Animation hooks are intentionally empty until character animations are implemented.
func animate_working(_delta: float) -> void:
	pass


func animate_eating(_delta: float) -> void:
	pass


func animate_walking(_delta: float) -> void:
	pass


func animate_dying() -> void:
	pass


func animate_at_home() -> void:
	pass
