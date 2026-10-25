class_name BuildCostText
extends RefCounted
## Shared wording for individual options and the total construction budget.

static func format(costs: Array[ResourceAmount]) -> String:
	var totals: Dictionary[StringName, int] = {}
	var names: Dictionary[StringName, String] = {}
	for cost in costs:
		if cost == null or cost.type == null or cost.amount < 0:
			return "Некорректная цена"
		totals[cost.type.id] = totals.get(cost.type.id, 0) + cost.amount
		names[cost.type.id] = cost.type.display_name
	var parts := PackedStringArray()
	for id in totals:
		if totals[id] > 0:
			parts.append("%d %s" % [totals[id], names[id]])
	return " + ".join(parts) if not parts.is_empty() else "Бесплатно"
