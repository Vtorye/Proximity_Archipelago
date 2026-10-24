class_name BuildController
extends Node

signal built(option: BuildOption, cell: Vector2i)

var map: TileMapLayer
var buildings: Node2D
var inventory: WorldInventory
var options: Array[BuildOption] = []
var _occupied: Dictionary[Vector2i, Node2D] = {}
var _blocked: Dictionary[Vector2i, bool] = {}
var _committing := false


func configure(tile_map: TileMapLayer, building_root: Node2D, stock: WorldInventory, catalog: Array[BuildOption]) -> void:
	map = tile_map
	buildings = building_root
	inventory = stock
	options = catalog


## Existing homes and workplaces reserve their cells, but remain accessible.
func reserve_existing(node: Node2D) -> void:
	_occupied[map.local_to_map(map.to_local(node.global_position))] = node


func blocked_cells() -> Array[Vector2i]:
	return _blocked.keys()


func unavailable_reason(option: BuildOption, cell: Vector2i) -> String:
	if _committing:
		return "Construction in progress"
	if option == null or not options.has(option):
		return "Unavailable option"
	if not inventory.can_afford(option.cost):
		return "Insufficient or unregistered resources"
	if option is TileBuildOption:
		var tile := option as TileBuildOption
		if not map.tile_set.has_source(tile.source_id):
			return "Invalid tile source"
		var source := map.tile_set.get_source(tile.source_id) as TileSetAtlasSource
		if source == null or not source.has_tile(tile.atlas_coords) or not source.has_alternative_tile(tile.atlas_coords, tile.alternative_tile):
			return "Invalid atlas tile"
		if map.get_cell_source_id(cell) == tile.source_id and map.get_cell_atlas_coords(cell) == tile.atlas_coords and map.get_cell_alternative_tile(cell) == tile.alternative_tile:
			return "Already placed"
	elif option is SceneBuildOption:
		var scene_option := option as SceneBuildOption
		if scene_option.scene == null or scene_option.occupied_cells.is_empty() or not scene_option.occupied_cells.has(Vector2i.ZERO):
			return "Invalid building definition"
	else:
		return "Unsupported option"
	for target in _footprint(option, cell):
		if map.get_cell_source_id(target) == -1:
			return "Outside the map"
		if option.allow_when_occupied:
			continue
		var occupant: Node2D = _occupied.get(target)
		if occupant != null and not _can_replace(option, occupant):
			if occupant is House and _builds_house(option):
				return "House already here"
			return "Cell occupied"
		# Without the override, people also occupy their cells.
		for human in get_tree().get_nodes_in_group("humans"):
			if human.get_viewport() == map.get_viewport() and map.local_to_map(map.to_local(human.global_position)) == target:
				# Residents of a building that is about to be replaced do not block it.
				if occupant != null and human.get("home") == occupant:
					continue
				return "Person on cell"
	return ""


func can_build(option: BuildOption, cell: Vector2i) -> bool:
	return unavailable_reason(option, cell).is_empty()


func try_build(option: BuildOption, cell: Vector2i) -> bool:
	if not can_build(option, cell):
		return false
	var instance: Building
	if option is SceneBuildOption:
		var candidate := (option as SceneBuildOption).scene.instantiate()
		if not candidate is Building:
			candidate.free()
			return false
		instance = candidate as Building
	# No awaits or notifications until the world and inventory agree.
	_committing = true
	if not inventory.try_spend(option.cost, false):
		if instance != null:
			instance.free()
		_committing = false
		return false
	if option is TileBuildOption:
		var tile := option as TileBuildOption
		map.set_cell(cell, tile.source_id, tile.atlas_coords, tile.alternative_tile)
	else:
		var scene_option := option as SceneBuildOption
		var footprint := _footprint(option, cell)
		for old in _occupants_of(footprint):
			_clear_occupant(old)
		instance.position = buildings.to_local(map.to_global(map.map_to_local(cell)))
		buildings.add_child(instance)
		for target in footprint:
			_occupied[target] = instance
			if scene_option.blocks_movement:
				_blocked[target] = true
		instance.setup(cell, option)
	HumanNavigation.generate(map, blocked_cells()) # вроде это просто надо закоментить чтобы 
	_committing = false
	inventory.changed.emit()
	built.emit(option, cell)
	return true


## Share of the build cost returned on demolition. 0 = no refund; raise to enable refunds.
const DEMOLISH_REFUND_RATIO := 0.0


## Empty string if the building on this cell can be demolished, otherwise the reason.
func can_demolish(cell: Vector2i) -> String:
	if _committing:
		return "Construction in progress"
	var occupant: Node2D = _occupied.get(cell)
	if occupant == null:
		return "Nothing to demolish"
	if not occupant is Building:
		return "Cannot demolish this"
	return ""


## Demolishes the building on the cell. No confirmation; residents die with DEMOLISHED.
func demolish_at(cell: Vector2i) -> bool:
	if not can_demolish(cell).is_empty():
		return false
	var building := _occupied[cell] as Building
	_committing = true
	_refund_for_demolish(building.option)
	_clear_occupant(building)
	HumanNavigation.generate(map, blocked_cells())
	_committing = false
	inventory.changed.emit()
	return true


## Returns part of the build cost. Buildings without an option (placed in the scene) refund nothing.
func _refund_for_demolish(option: BuildOption) -> void:
	if option == null or option.cost == null or option.cost.type == null:
		return
	var amount := floori(option.cost.amount * DEMOLISH_REFUND_RATIO)
	if amount > 0:
		inventory.add(option.cost.type, amount)


func _footprint(option: BuildOption, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if option is SceneBuildOption:
		for offset in (option as SceneBuildOption).occupied_cells:
			if not cells.has(origin + offset):
				cells.append(origin + offset)
	else:
		cells.append(origin)
	return cells


## Unique buildings currently registered on the given cells.
func _occupants_of(cells: Array[Vector2i]) -> Array[Node2D]:
	var found: Array[Node2D] = []
	for target in cells:
		var occupant: Node2D = _occupied.get(target)
		if occupant != null and not found.has(occupant):
			found.append(occupant)
	return found


## Removes a building and every cell record that points to it.
func _clear_occupant(old: Node2D) -> void:
	for key in _occupied.keys():
		if _occupied[key] == old:
			_occupied.erase(key)
			_blocked.erase(key)
	if old is Building:
		(old as Building).demolish()
		old.free()
	else:
		old.queue_free()


func _can_replace(option: BuildOption, occupant: Node2D) -> bool:
	if not option is SceneBuildOption or not occupant is Building:
		return false
	return not (occupant is House and _builds_house(option))


func _builds_house(option: BuildOption) -> bool:
	if not option is SceneBuildOption:
		return false
	var scene := (option as SceneBuildOption).scene
	if scene == null:
		return false
	var probe := scene.instantiate()
	var is_house := probe is House
	probe.free()
	return is_house
