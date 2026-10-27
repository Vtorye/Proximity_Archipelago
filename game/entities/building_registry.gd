class_name BuildingRegistry
extends Node
## World-local membership and occupancy; all exits unregister synchronously.

signal added(building: Building)
signal removed(building: Building)
signal changed
var _buildings: Array[Building] = []
var _occupied: Dictionary[Vector2i, Building] = {}
var _footprints: Dictionary[Building, Array] = {}

func register(building: Building) -> void:
	if _buildings.has(building):
		return
	var cells: Array[Vector2i] = building.footprint()
	_buildings.append(building)
	_footprints[building] = cells
	for cell in cells:
		_occupied[cell] = building
	building.tree_exiting.connect(_unregister.bind(building), CONNECT_ONE_SHOT)
	building.demolished.connect(_unregister)
	added.emit(building)
	changed.emit()

func _unregister(building: Building) -> void:
	if not _buildings.has(building):
		return
	for cell in _footprints[building]:
		if _occupied.get(cell) == building:
			_occupied.erase(cell)
	_footprints.erase(building)
	_buildings.erase(building)
	removed.emit(building)
	changed.emit()

func all() -> Array[Building]:
	return _buildings.duplicate()

func workplaces() -> Array[Workplace]:
	var result: Array[Workplace] = []
	for building in _buildings:
		if building is Workplace:
			result.append(building)
	return result

func canteens() -> Array[Canteen]:
	var result: Array[Canteen] = []
	for building in _buildings:
		if building is Canteen:
			result.append(building)
	return result

func at(cell: Vector2i) -> Building:
	return _occupied.get(cell)

func blocked_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for building in _buildings:
		if building.option is SceneBuildOption and building.option.blocks_movement:
			result.append_array(building.footprint())
	return result
