class_name PriceService
extends Node
## Prices derive from immutable base definitions and event history, never from prior quotes.
signal changed

@export_range(0.1, 10.0, 0.1, "or_greater") var reload_interval_seconds := 1.0
var _events := WorldEvents.new()
var _global_multiplier := 1.0
var _terrain_multiplier: Callable
var _definitions: Array[BuildOption] = []
var _reloaded: Dictionary[String, BuildOption] = {}
var _stamps: Dictionary[String, String] = {}
var _elapsed := 0.0
var errors: Array[String] = []
var _orders: Dictionary[String, int] = {}

func _init() -> void:
	_events.occurred.connect(func(_event: int, _subject: StringName, _amount: int): changed.emit())

func configure_terrain(multiplier: Callable) -> void:
	_terrain_multiplier = multiplier

func track_options(options: Array[BuildOption]) -> void:
	_definitions = options.duplicate()
	changed.emit()

func tracks(option: BuildOption) -> bool:
	return _definitions.has(option)

func multiplier() -> float:
	return _global_multiplier

func apply_multiplier(factor: float) -> void:
	_global_multiplier *= factor
	changed.emit()

func capture_state() -> Dictionary:
	return {"multiplier": _global_multiplier, "counts": _events.capture_counts()}

func restore_state(state: Dictionary) -> void:
	_global_multiplier = state.multiplier
	_events.restore_counts(state.counts)
	changed.emit()

func record(event: GameEvents.Kind, subject: StringName = &"", amount: int = 1) -> void:
	_events.publish(event, subject, amount)

func event_count(event: GameEvents.Kind, subject: StringName) -> int:
	return _events.count(event, subject)

func base_costs(option: BuildOption) -> Array[ResourceAmount]:
	return _price_definition(option).costs.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)

func price_rules(option: BuildOption) -> Array[PriceRule]:
	return _price_definition(option).price_rules.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)

func _price_definition(option: BuildOption) -> BuildOption:
	return _reloaded.get(option.resource_path, option)

static func key(event: int, subject: StringName) -> String:
	return GameEvents.key(event, subject)

func quote(option: BuildOption, pending: Dictionary[String, int] = {}, local_multiplier: float = 1.0) -> Array[ResourceAmount]:
	if option == null: return [null]
	var definition := _price_definition(option)
	if not valid(definition): return [null]
	var totals: Dictionary[StringName, float] = {}
	var types: Dictionary[StringName, ResourceType] = {}
	for entry in definition.costs:
		if entry == null or entry.type == null or entry.amount < 0: return [null]
		types[entry.type.id] = entry.type
		totals[entry.type.id] = totals.get(entry.type.id, 0.0) + entry.amount
	for rule in definition.price_rules:
		if rule == null or rule.value < 0 or not is_finite(rule.value): return [null]
		var id: String = key(rule.event, rule.subject)
		var count: int = _events.count(rule.event, rule.subject) + _orders.get(id, 0) + pending.get(id, 0)
		for type in totals:
			if rule.resource == null or rule.resource.id == type:
				totals[type] = totals[type] * pow(rule.value, count) if rule.operation == 0 else totals[type] + rule.value * count
	var result: Array[ResourceAmount] = []
	for type in totals:
		if totals[type] < 0 or not is_finite(totals[type]) or totals[type] > 2147483647: return [null]
		var entry := ResourceAmount.new()
		entry.type = types[type]
		entry.amount = ceili(totals[type] * _global_multiplier * local_multiplier - 0.000001)
		result.append(entry)
	return result

func quote_plan(commands: Array[BuildCommand]) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	for entries: Array in quote_commands(commands).values(): result.append_array(entries)
	return result

## A single sequential quote funds each individual site as well as the complete plan.
func quote_commands(commands: Array[BuildCommand]) -> Dictionary:
	var result: Dictionary = {}
	var pending: Dictionary[String, int] = {}
	# Demolition commits before construction, regardless of brush insertion order.
	for command in commands:
		if command == null: return {null: [null]}
		if not command.is_removal(): continue
		var building: Building = command.removed_building
		if not is_instance_valid(building): return {null: [null]}
		if building is ConstructionSite:
			var reserved_event: GameEvents.Kind = GameEvents.Kind.TERRAIN_CHANGED if building.option is TileBuildOption else GameEvents.Kind.BUILDING_BUILT
			for filter in [building.option.id, &""]:
				var reserved_key: String = key(reserved_event, filter)
				pending[reserved_key] = pending.get(reserved_key, 0) - 1
			continue
		var subject: StringName = building.improvement.id if building is Workplace and building.improvement != null else (building.option.id if building.option != null else &"initial")
		for filter in [subject, &""]:
			var id: String = key(GameEvents.Kind.BUILDING_DEMOLISHED, filter)
			pending[id] = pending.get(id, 0) + 1
	for command in commands:
		if command == null: return {null: [null]}
		if command.is_removal(): continue
		if command.option == null: return {null: [null]}
		result[command] = quote_at(command.option, command.cell, pending)
		for subject in [command.option.id, &""]:
			var event: GameEvents.Kind = GameEvents.Kind.TERRAIN_CHANGED if command.option is TileBuildOption else GameEvents.Kind.BUILDING_BUILT
			var id: String = key(event, subject)
			pending[id] = pending.get(id, 0) + 1
	return result

func quote_at(option: BuildOption, cell: Vector2i, pending: Dictionary[String, int] = {}) -> Array[ResourceAmount]:
	var factor: float = _terrain_multiplier.call(option, cell) if _terrain_multiplier.is_valid() else 1.0
	return quote(option, pending, factor)

func queue_order(option: BuildOption, delta: int) -> void:
	var event: GameEvents.Kind = GameEvents.Kind.TERRAIN_CHANGED if option is TileBuildOption else GameEvents.Kind.BUILDING_BUILT
	for subject in [option.id, &""]:
		var id: String = key(event, subject)
		_orders[id] = maxi(0, _orders.get(id, 0) + delta)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < reload_interval_seconds: return
	_elapsed = 0.0
	var paths: Dictionary[String, bool] = {}
	var dependencies: Dictionary[BuildOption, PackedStringArray] = {}
	for option in _definitions:
		if option == null or not FileAccess.file_exists(option.resource_path): continue
		var files := PackedStringArray([option.resource_path])
		paths[option.resource_path] = true
		for dependency in ResourceLoader.get_dependencies(option.resource_path):
			var path := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
			if path.get_extension() in ["tres", "res"] and FileAccess.file_exists(path):
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
			_reloaded[option.resource_path] = candidate
		else: errors.append(option.resource_path + ": invalid price edit; retaining previous valid definition")
	changed.emit()

func valid(option: BuildOption) -> bool:
	for cost in option.costs:
		if cost == null or cost.type == null or cost.amount < 0: return false
	for rule in option.price_rules:
		if rule == null or rule.event < 0 or rule.event >= GameEvents.Kind.size() or rule.operation not in [0, 1] or rule.value < 0 or not is_finite(rule.value): return false
	return true
