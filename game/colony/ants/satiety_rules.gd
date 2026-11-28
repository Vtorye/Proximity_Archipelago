class_name SatietyRules
extends Resource
## Energy consumed per second, meal timing, and reserves used by action planning.

@export_group("Energy per Second")
@export_range(0.01, 100.0, 0.01, "or_greater") var walk_rate := 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var work_rate := 1.2
@export_range(0.0, 100.0, 0.01, "or_greater") var rest_rate := 0.8
@export_range(0.0, 100.0, 0.01, "or_greater") var eat_rate := 0.25

@export_group("Meals")
@export_range(0.01, 60.0, 0.01, "or_greater") var meal_seconds := 2.0
## Minimum energy remaining after completing a planned action and reaching food.
@export_range(0.0, 100.0, 0.1, "or_greater") var safety_margin := 8.0

@export_group("Action Reserves")
@export_range(0.0, 100.0, 0.1, "or_greater") var travel_reserve := 2.0
@export_range(0.0, 100.0, 0.1, "or_greater") var construction_reserve := 1.0
@export_range(0.0, 100.0, 0.1, "or_greater") var combat_reserve := 4.0

func meal_energy() -> float:
	return meal_seconds * eat_rate

func is_valid() -> bool:
	for value in [walk_rate, work_rate, rest_rate, eat_rate, meal_seconds, safety_margin, travel_reserve, construction_reserve, combat_reserve]:
		if not is_finite(value) or value < 0.0:
			return false
	return walk_rate > 0.0 and meal_seconds > 0.0
