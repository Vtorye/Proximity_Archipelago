class_name PriceService
extends Node
## Prices derive from immutable base definitions and event history, never from prior quotes.
signal changed
var events := WorldEvents.new()
var definitions: Array[BuildOption] = []
var _stamps: Dictionary[String, String] = {}
var _elapsed := 0.0
var errors: Array[String] = []

func _ready() -> void:
	_process(1.0)

func _init() -> void:
	events.occurred.connect(func(_event: int, _subject: StringName, _amount: int): changed.emit())

func record(event: GameEvents.Kind, subject: StringName, amount: int = 1) -> void:
	events.publish(event, subject, amount)

static func key(event: int, subject: StringName) -> String:
	return GameEvents.key(event, subject)

func quote(option: BuildOption, pending: Dictionary[String, int] = {}) -> Array[ResourceAmount]:
	if option == null or not valid(option): return [null]
	var totals: Dictionary[StringName, float] = {}
	var types: Dictionary[StringName, ResourceType] = {}
	for entry in option.costs:
		if entry == null or entry.type == null or entry.amount < 0: return [null]
		types[entry.type.id] = entry.type
		totals[entry.type.id] = totals.get(entry.type.id, 0.0) + entry.amount
	for rule in option.price_rules:
		if rule == null or rule.value < 0 or not is_finite(rule.value): return [null]
		var id: String = key(rule.event, rule.subject)
		var count: int = events.count(rule.event, rule.subject) + pending.get(id, 0)
		for type in totals:
			if rule.resource == null or rule.resource.id == type:
				totals[type] = totals[type] * pow(rule.value, count) if rule.operation == 0 else totals[type] + rule.value * count
	var result: Array[ResourceAmount] = []
	for type in totals:
		if totals[type] < 0 or not is_finite(totals[type]) or totals[type] > 2147483647: return [null]
		var entry := ResourceAmount.new()
		entry.type = types[type]
		entry.amount = ceili(totals[type] - 0.000001)
		result.append(entry)
	return result

func quote_plan(commands: Array[BuildCommand]) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	var pending: Dictionary[String, int] = {}
	# Demolition commits before construction, regardless of brush insertion order.
	for command in commands:
		if command == null: return [null]
		if not command.is_removal(): continue
		var building: Building = command.removed_building
		if not is_instance_valid(building): return [null]
		var subject: StringName = building.option.id if building.option != null else &"initial"
		for filter in [subject, &""]:
			var id: String = key(GameEvents.Kind.BUILDING_DEMOLISHED, filter)
			pending[id] = pending.get(id, 0) + 1
	for command in commands:
		if command == null: return [null]
		if command.is_removal(): continue
		if command.option == null: return [null]
		result.append_array(quote(command.option, pending))
		for subject in [command.option.id, &""]:
			var event: GameEvents.Kind = GameEvents.Kind.BUILDING_BUILT if command.option is SceneBuildOption else GameEvents.Kind.TERRAIN_CHANGED
			var id: String = key(event, subject)
			pending[id] = pending.get(id, 0) + 1
	return result

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	var paths: Dictionary[String, bool] = {}
	var dependencies: Dictionary[BuildOption, Array] = {}
	for option in definitions:
		if option == null: continue
		var files: Array[String] = []
		var resources: Array[Resource] = [option]
		resources.append_array(option.costs)
		resources.append_array(option.price_rules)
		for resource in resources:
			if resource == null: continue
			var path: String = resource.resource_path
			if path.is_empty() or path.contains("::") or not FileAccess.file_exists(path): continue
			files.append(path)
			paths[path] = true
		dependencies[option] = files
	var changed_paths: Dictionary[String, bool] = {}
	for path in paths:
		var stamp: String = FileAccess.get_sha256(path)
		if _stamps.has(path) and _stamps[path] != stamp: changed_paths[path] = true
		_stamps[path] = stamp
	if changed_paths.is_empty(): return
	errors.clear()
	for option in dependencies:
		var reload_needed := false
		for path in dependencies[option]: reload_needed = reload_needed or changed_paths.has(path)
		if not reload_needed or option.resource_path.is_empty(): continue
		# Load independently first: malformed edits cannot replace the running definition.
		var candidate: BuildOption = ResourceLoader.load(option.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as BuildOption
		if candidate != null and valid(candidate):
			option.costs = candidate.costs
			option.price_rules = candidate.price_rules
		else: errors.append(option.resource_path + ": invalid price edit; retaining previous valid definition")
	changed.emit()

func valid(option: BuildOption) -> bool:
	for cost in option.costs:
		if cost == null or cost.type == null or cost.amount < 0: return false
	for rule in option.price_rules:
		if rule == null or rule.event < 0 or rule.event >= GameEvents.Kind.size() or rule.operation not in [0, 1] or rule.value < 0 or not is_finite(rule.value): return false
	return true
