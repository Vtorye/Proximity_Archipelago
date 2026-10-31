class_name MatchSummary
extends RefCounted
var development_level := 0
var tasks_completed := 0
var tasks_skipped := 0
## Immutable values captured when a match commits its result.

var won: bool
var reason: StringName
var time_left: float
var resources: Array[ResourceAmount] = []

static func capture(victory: bool, cause: StringName, seconds: float, stock: WorldInventory) -> MatchSummary:
	var summary := MatchSummary.new()
	summary.won = victory
	summary.reason = cause
	summary.time_left = seconds
	for type in stock.registered_types():
		var entry := ResourceAmount.new()
		entry.type = type
		entry.amount = stock.quantity(type)
		summary.resources.append(entry)
	return summary
