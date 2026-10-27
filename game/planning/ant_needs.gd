class_name AntNeeds
extends RefCounted
## Satiety is measured in energy units, consumed continuously in simulation time.

const WALK_RATE := 1.0
const WORK_RATE := 1.2
const REST_RATE := 0.25
const EAT_RATE := 0.25
const SAFETY_MARGIN := 8.0
const MEAL_SECONDS := 2.0
const CAPACITY := 120.0
var satiety := CAPACITY

func consume(delta: float, rate: float) -> void:
	satiety = maxf(0.0, satiety - maxf(delta, 0.0) * rate)

func eat() -> void:
	satiety = CAPACITY

func can_afford(cost: float) -> bool:
	return is_finite(cost) and satiety >= cost + SAFETY_MARGIN
