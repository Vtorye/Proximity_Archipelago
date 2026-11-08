class_name AntNeeds
extends RefCounted
## Satiety is measured in energy units, consumed continuously in simulation time.

const WALK_RATE := 1.0
const WORK_RATE := 1.2
## A full ant can rest for 150 seconds without a meal.
const REST_RATE := 0.8
const EAT_RATE := 0.25
const SAFETY_MARGIN := 8.0
const MEAL_SECONDS := 2.0
const CAPACITY := 120.0
var capacity := CAPACITY
var satiety := CAPACITY

func configure(maximum: float) -> void:
	capacity = maxf(1.0, maximum)
	satiety = capacity

func fraction() -> float:
	return satiety / capacity

func consume(delta: float, rate: float) -> void:
	satiety = maxf(0.0, satiety - maxf(delta, 0.0) * rate)

func eat() -> void:
	satiety = capacity

func can_afford(cost: float) -> bool:
	return is_finite(cost) and satiety >= cost + SAFETY_MARGIN
