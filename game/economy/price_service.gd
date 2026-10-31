class_name PriceService
extends Node
## Prices derive from immutable base definitions and event history, never from prior quotes.
signal changed
signal occurred(event: GameEvents.Kind, subject: StringName, amount: int)
var _counts: Dictionary[String, int] = {}
var definitions: Array[BuildOption] = []
var _stamps: Dictionary[String, String] = {}
var _elapsed := 0.0
var errors: Array[String] = []

func record(event: GameEvents.Kind, subject: StringName, amount: int = 1) -> void:
	_counts[key(event, subject)] = _counts.get(key(event, subject), 0) + amount
	_counts[key(event, &"")] = _counts.get(key(event, &""), 0) + amount if subject != &"" else _counts[key(event, &"")]
	occurred.emit(event, subject, amount)
	changed.emit()

static func key(event: int, subject: StringName) -> String:
	return "%d:%s" % [event, subject]

func quote(option: BuildOption, pending: Dictionary[String, int] = {}) -> Array[ResourceAmount]:
	if option == null: return [null]
	var totals: Dictionary[ResourceType, float] = {}
	for entry in option.costs:
		if entry == null or entry.type == null: return [null]
		totals[entry.type] = totals.get(entry.type, 0.0) + entry.amount
	for rule in option.price_rules:
		if rule == null or rule.value < 0 or not is_finite(rule.value): return [null]
		var id: String = key(rule.event, rule.subject)
		var count: int = _counts.get(id, 0) + pending.get(id, 0)
		for type in totals:
			if rule.resource == null or rule.resource.id == type.id:
				totals[type] = totals[type] * pow(rule.value, count) if rule.operation == 0 else totals[type] + rule.value * count
	var result: Array[ResourceAmount] = []
	for type in totals:
		if totals[type] < 0 or not is_finite(totals[type]) or totals[type] > 2147483647: return [null]
		var entry := ResourceAmount.new()
		entry.type = type
		entry.amount = ceili(totals[type] - 0.000001)
		result.append(entry)
	return result

func quote_plan(commands: Array[BuildCommand]) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	var pending: Dictionary[String, int] = {}
	for command in commands:
		if command == null: return [null]
		if command.is_removal(): continue
		if command.option == null: return [null]
		result.append_array(quote(command.option, pending))
		for subject in [command.option.id, &""]:
			var id: String = key(GameEvents.Kind.BUILDING_BUILT, subject)
			pending[id] = pending.get(id, 0) + 1
	return result

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	for option in definitions:
		if option == null or option.resource_path.is_empty(): continue
		var path: String = option.resource_path
		var stamp: String = FileAccess.get_sha256(path)
		if _stamps.has(path) and _stamps[path] != stamp:
			# Load independently first: malformed edits cannot replace the running definition.
			var candidate: BuildOption = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as BuildOption
			if candidate != null and valid(candidate):
				option.costs = candidate.costs
				option.price_rules = candidate.price_rules
				changed.emit()
		_stamps[path] = stamp

func valid(option: BuildOption) -> bool:
	for cost in option.costs:
		if cost == null or cost.type == null or cost.amount < 0: return false
	for rule in option.price_rules:
		if rule == null or rule.event < 0 or rule.event >= GameEvents.Kind.size() or rule.operation not in [0, 1] or rule.value < 0 or not is_finite(rule.value): return false
	return true
