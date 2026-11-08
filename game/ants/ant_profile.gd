class_name AntProfile
extends Resource
## Shared designer definition. Every resident owns separate needs and health.
@export var title := "Worker"
@export_range(1, 10000) var satiety_capacity := 120.0
@export_range(0.05, 0.95) var meal_fraction := 0.5
@export_range(1, 128) var speed := 24.0
@export_range(0.1, 60) var work_seconds := 3.0
@export_range(1, 100) var carry_capacity := 2
@export_range(1, 1000) var health := 1
@export_range(1, 100) var damage := 1

func validate() -> Array[String]:
	var errors: Array[String] = []
	for key in ["satiety_capacity", "speed", "work_seconds", "carry_capacity", "health", "damage"]:
		var value: float = float(get(key))
		if not is_finite(value) or value <= 0: errors.append(resource_path + ": " + key + " must be positive")
	if not is_finite(meal_fraction) or meal_fraction <= 0 or meal_fraction >= 1:
		errors.append(resource_path + ": meal_fraction must be between zero and one")
	return errors
