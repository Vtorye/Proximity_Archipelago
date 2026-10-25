class_name BuildDraft
extends RefCounted
## A reversible plan. Painting never changes the world, stock, or active navigation.
signal changed
var controller: BuildController
var last_result := PlacementCheck.new()
var _commands: Dictionary[Vector2i, BuildOption] = {}
var _history: Array[Dictionary] = []
var _stroke: Dictionary[Vector2i, BuildOption] = {}
var _painting := false

func commands() -> Dictionary[Vector2i, BuildOption]:
	return _commands.duplicate()

func size() -> int:
	return _commands.size()

func begin_stroke() -> void:
	if _painting: return
	_stroke = _commands.duplicate()
	_painting = true

func end_stroke() -> void:
	if not _painting: return
	if _commands != _stroke: _history.append(_stroke)
	_stroke = {}
	_painting = false

func paint(option: BuildOption, cell: Vector2i) -> bool:
	last_result = controller.placement_check(option, cell)
	if last_result.code == PlacementCheck.Code.ALREADY_PLACED and _commands.has(cell):
		_commands.erase(cell)
		last_result = PlacementCheck.new()
		changed.emit()
		return true
	if not last_result.allowed():
		return false
	if _commands.get(cell) == option:
		return true
	var footprint: Array[Vector2i] = controller.footprint_at(option, cell)
	for origin in _commands:
		if origin == cell: continue
		for target in controller.footprint_at(_commands[origin], origin):
			if footprint.has(target):
				last_result = PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
				return false
	_commands[cell] = option
	changed.emit()
	return true

func undo() -> void:
	end_stroke()
	if _history.is_empty(): return
	_commands.assign(_history.pop_back())
	last_result = PlacementCheck.new()
	changed.emit()

func can_undo() -> bool:
	return not _history.is_empty() or _painting and _commands != _stroke

func clear() -> void:
	_commands.clear()
	_history.clear()
	_stroke.clear()
	_painting = false
	last_result = PlacementCheck.new()
	changed.emit()

func costs() -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	for option in _commands.values(): result.append_array(option.costs)
	return result

func budget_check() -> PlacementCheck:
	if not controller.inventory.can_afford_all(costs()):
		return PlacementCheck.result(PlacementCheck.Code.RESOURCES)
	var food: ResourceType = controller.inventory.type_by_id(&"food")
	var meals := 0
	var food_cost := 0
	for option in _commands.values():
		food_cost += option.cost_amount(food)
		if option is SceneBuildOption: meals += option.spawn_count
	if controller.inventory.available(food) - food_cost < meals:
		return PlacementCheck.result(PlacementCheck.Code.SPAWN_FOOD)
	return PlacementCheck.new()

func commit() -> bool:
	end_stroke()
	if not controller.try_build_batch(_commands):
		last_result = controller.last_result
		changed.emit()
		return false
	clear()
	return true

