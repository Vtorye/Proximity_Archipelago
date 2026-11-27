class_name AntProfile
extends Resource
## Shared designer definition. Every resident owns separate needs and health.
@export var title := "ui.nest.worker"
@export_range(1, 10000) var satiety_capacity := 120.0
@export_range(0.05, 0.95) var meal_fraction := 0.5
@export_range(1, 128) var speed := 24.0
@export_range(0.1, 60) var work_seconds := 3.0
@export_range(1, 100) var carry_capacity := 2
@export_range(1, 1000) var health := 1
@export_range(1, 100) var damage := 1

@export_group("Action Timing")
@export var departure_wait_range := Vector2(0.3, 0.5)
@export var wander_wait_range := Vector2(0.2, 0.7)
@export_range(0.05, 60.0, 0.05, "or_greater", "suffix:s") var retry_seconds := 1.0
@export_range(0.05, 60.0, 0.05, "or_greater", "suffix:s") var work_queue_wait_seconds := 0.75
@export_range(0.0, 60.0, 0.05, "or_greater", "suffix:s") var return_home_wait_seconds := 0.5
@export_range(0.0, 60.0, 0.05, "or_greater", "suffix:s") var warrior_meal_wait_seconds := 0.3
@export_range(0.0, 60.0, 0.05, "or_greater", "suffix:s") var flee_wait_seconds := 0.2
@export_range(1, 32, 1, "or_greater") var wander_radius := 2

func validate() -> Array[String]:
	var errors: Array[String] = []
	for key in ["satiety_capacity", "speed", "work_seconds", "carry_capacity", "health", "damage"]:
		var value: float = float(get(key))
		if not is_finite(value) or value <= 0: errors.append(resource_path + ": " + key + " must be positive")
	for wait_range in [departure_wait_range, wander_wait_range]:
		if not wait_range.is_finite() or wait_range.x < 0.0 or wait_range.y < wait_range.x:
			errors.append(resource_path + ": action delay range must be ordered and nonnegative")
	for pause in [retry_seconds, work_queue_wait_seconds, return_home_wait_seconds, warrior_meal_wait_seconds, flee_wait_seconds]:
		if not is_finite(pause) or pause < 0.0:
			errors.append(resource_path + ": action delays must be finite and nonnegative")
	if wander_radius < 1:
		errors.append(resource_path + ": wander radius must be positive")
	if not is_finite(meal_fraction) or meal_fraction <= 0 or meal_fraction >= 1:
		errors.append(resource_path + ": meal_fraction must be between zero and one")
	return errors
