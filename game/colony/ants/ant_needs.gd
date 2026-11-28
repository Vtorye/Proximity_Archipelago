class_name AntNeeds
extends RefCounted
## Satiety is measured in energy units, consumed continuously in simulation time.

var rules: SatietyRules
var capacity: float
var satiety: float
var safety_margin: float:
	get:
		return rules.safety_margin

func configure(maximum: float) -> void:
	capacity = maxf(1.0, maximum)
	satiety = capacity

func fraction() -> float:
	return satiety / capacity

func scale_capacity(factor: float) -> void:
	capacity *= factor
	satiety *= factor

func consume(delta: float, rate: float) -> void:
	satiety = maxf(0.0, satiety - maxf(delta, 0.0) * rate)

func eat() -> void:
	satiety = capacity

func can_afford(cost: float) -> bool:
	return is_finite(cost) and satiety >= cost + safety_margin
