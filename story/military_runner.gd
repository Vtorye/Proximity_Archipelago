extends AntAgent
## A story actor uses the warrior's animation without joining the colony simulation.

var _previous_position: Vector2

func _ready() -> void:
	role = Role.WARRIOR
	status = Status.WALKING
	_previous_position = global_position
	_refresh_visual()

func _physics_process(delta: float) -> void:
	var movement := global_position - _previous_position
	if not movement.is_zero_approx():
		_last_direction = movement.normalized()
		_animation_time += delta
	_previous_position = global_position
	_refresh_visual()
