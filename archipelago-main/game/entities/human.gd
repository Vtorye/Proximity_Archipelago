extends Node2D

enum Status {
	WALKING,
	HOME,
	WORKING,
	EATING
}

@export var rot_speed: float = 6.0
@export var speed: float = 16.0
@export var work_time: float = 3.0
@export var eat_time: float = 3.0
@export var home_time: float = 3.0
@export var starting_food: int = 3
@export var eat_bonus: int = 3

@export var home: Node2D
@export var work: Node2D
@export var food: Node2D

@onready var nav: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite

var food_left: int
var work_left_seconds: float
var eat_left_seconds: float
var home_left_seconds: float

var status: Status = Status.HOME

var target: Node2D:
	set(value):
		target = value
		nav.target_position = target.position + Vector2.ONE.rotated(randf_range(0, PI*2)) * randf_range(4, 8)

func _ready() -> void:
	assert(home, "Human " + str(name) + " has no home")
	assert(work, "Human " + str(name) + " has nowhere to work")
	assert(food, "Human " + str(name) + " has nowhere to eat")
	
	food_left = randi_range(1, starting_food)
	work_left_seconds = work_time
	eat_left_seconds = eat_time
	home_left_seconds = randf_range(1.0, home_time)

func _physics_process(delta: float) -> void:
	match status:
		Status.HOME:
			home_left_seconds -= delta
			if home_left_seconds <= 0:
				home_left_seconds = home_time
				if food_left > 0:
					target = work
					status = Status.WALKING
				else:
					target = food
					status = Status.WALKING
		Status.WORKING:
			work_left_seconds -= delta
			sprite.rotate(delta*rot_speed)
			if work_left_seconds <= 0:
				sprite.rotation = 0
				work_left_seconds = work_time
				food_left -= 1
				target = home
				status = Status.WALKING
		Status.EATING:
			eat_left_seconds -= delta
			sprite.rotate(delta*rot_speed)
			if eat_left_seconds <= 0:
				sprite.rotation = 0
				eat_left_seconds = eat_time
				food_left += eat_bonus
				target = home
				status = Status.WALKING
		Status.WALKING:
			if navigate(delta):
				if target == home:
					status = Status.HOME
				elif target == food:
					status = Status.EATING
				elif target == work:
					status = Status.WORKING

func navigate(delta: float) -> bool:
	var target_pos := nav.get_next_path_position()
	var dir := (target_pos - position).normalized()
	position += dir * speed * delta
	return nav.is_target_reached()
