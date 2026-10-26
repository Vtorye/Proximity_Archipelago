class_name BuildDraft
extends RefCounted
## A reversible plan. Painting never changes the world, stock, or active navigation.
signal changed
var controller: BuildController
var last_result := PlacementCheck.new()
var _commands: Array[BuildCommand] = []
var _occupied: Dictionary[Vector2i, BuildCommand] = {}
var _terrain: Dictionary[Vector2i, BuildCommand] = {}
var _removed: Array[Building] = []
var _history: Array[Array] = []
var _stroke: Array[BuildCommand] = []
var _painting := false

func commands() -> Array[BuildCommand]:
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
	_stroke = []
	_painting = false

func paint(option: BuildOption, cell: Vector2i) -> bool:
	last_result = controller.placement_check(option, cell, removals())
	var previous: BuildCommand = _terrain.get(cell) if option is TileBuildOption else _occupied.get(cell)
	if last_result.code == PlacementCheck.Code.ALREADY_PLACED and previous != null:
		_erase(previous)
		last_result = PlacementCheck.new()
		changed.emit()
		return true
	if not last_result.allowed(): return false
	if previous != null and previous.cell == cell and previous.option == option: return true
	if option is SceneBuildOption:
		for target in controller.footprint_at(option, cell):
			if _occupied.has(target) and _occupied[target] != previous:
				last_result = PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
				return false
		if previous != null and previous.cell != cell:
			last_result = PlacementCheck.result(PlacementCheck.Code.OCCUPIED)
			return false
	if previous != null: _erase(previous)
	var command: BuildCommand = BuildCommand.create(cell, option)
	_commands.append(command)
	_index(command)
	changed.emit()
	return true

## Right click removes exactly the most recently added layer touching this cell.
func remove_last(cell: Vector2i) -> bool:
	for index in range(_commands.size() - 1, -1, -1):
		var command: BuildCommand = _commands[index]
		if footprint(command).has(cell):
			_erase(command)
			last_result = PlacementCheck.new()
			changed.emit()
			return true
	return false

func undo() -> void:
	end_stroke()
	if _history.is_empty(): return
	_commands.assign(_history.pop_back())
	_reindex()
	last_result = PlacementCheck.new()
	changed.emit()

func can_undo() -> bool:
	return not _history.is_empty() or _painting and _commands != _stroke

func clear() -> void:
	_commands.clear()
	_occupied.clear()
	_terrain.clear()
	_removed.clear()
	_history.clear()
	_stroke.clear()
	_painting = false
	last_result = PlacementCheck.new()
	changed.emit()

func costs() -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	for command in _commands:
		if not command.is_removal(): result.append_array(command.option.costs)
	return result

func budget_check() -> PlacementCheck:
	if not controller.inventory.can_afford_all(costs()):
		return PlacementCheck.result(PlacementCheck.Code.RESOURCES)
	var food: ResourceType = controller.inventory.type_by_id(&"food")
	var meals := 0
	var food_cost := 0
	for command in _commands:
		if command.is_removal(): continue
		var option: BuildOption = command.option
		food_cost += option.cost_amount(food)
		if option is SceneBuildOption: meals += option.spawn_count
	if controller.inventory.available(food) - food_cost < meals:
		return PlacementCheck.result(PlacementCheck.Code.SPAWN_FOOD)
	return PlacementCheck.new()

func commit() -> bool:
	end_stroke()
	if not controller.try_build_plan(_commands):
		last_result = controller.last_result
		changed.emit()
		return false
	clear()
	return true

func _reindex() -> void:
	_occupied.clear()
	_terrain.clear()
	_removed.clear()
	for command in _commands: _index(command)

func _index(command: BuildCommand) -> void:
	if command.is_removal():
		_removed.append(command.removed_building)
	elif command.option is TileBuildOption:
		_terrain[command.cell] = command
	else:
		for target in controller.footprint_at(command.option, command.cell):
			_occupied[target] = command

func _erase(command: BuildCommand) -> void:
	_commands.erase(command)
	if command.is_removal():
		_removed.erase(command.removed_building)
	elif command.option is TileBuildOption:
		_terrain.erase(command.cell)
	else:
		for target in controller.footprint_at(command.option, command.cell):
			_occupied.erase(target)

func removals() -> Array[Building]:
	return _removed.duplicate()

func footprint(command: BuildCommand) -> Array[Vector2i]:
	return command.removed_building.footprint() if command.is_removal() else controller.footprint_at(command.option, command.cell)

func demolition_check(cell: Vector2i) -> PlacementCheck:
	var building: Building = controller.registry.at(cell)
	if building != null:
		if removals().has(building): return PlacementCheck.result(PlacementCheck.Code.ALREADY_PLACED)
		return controller.demolition_check(cell)
	for option in controller.options:
		if option.id == &"ground": return controller.placement_check(option, cell)
	return PlacementCheck.result(PlacementCheck.Code.NO_BUILDING)

func demolish(cell: Vector2i) -> bool:
	# Repeated brush visits must not peel layers or toggle demolition marks.
	var building: Building = controller.registry.at(cell)
	if building != null and removals().has(building): return true
	last_result = demolition_check(cell)
	if not last_result.allowed(): return false
	if building != null:
		var command: BuildCommand = BuildCommand.remove(building)
		_commands.append(command)
		_index(command)
		changed.emit()
		return true
	for option in controller.options:
		if option.id == &"ground": return paint(option, cell)
	return false

func residents_to_demolish() -> int:
	var result := 0
	for building in removals():
		if building is House: result += building.residents.size()
	return result
