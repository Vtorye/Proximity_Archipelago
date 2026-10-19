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
		if _occupied.has(target):
			return "Cell occupied"
		# Without the override, people also occupy their cells.
		for human in get_tree().get_nodes_in_group("humans"):
			if human.get_viewport() == map.get_viewport() and map.local_to_map(map.to_local(human.global_position)) == target:
				return "Person on cell"
	return ""


func can_build(option: BuildOption, cell: Vector2i) -> bool:
	return unavailable_reason(option, cell).is_empty()


func try_build(option: BuildOption, cell: Vector2i) -> bool:
	if not can_build(option, cell):
		return false
	var instance: Node2D
	if option is SceneBuildOption:
		var candidate := (option as SceneBuildOption).scene.instantiate()
		if not candidate is Node2D:
			candidate.free()
			return false
		instance = candidate as Node2D
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
		instance.position = buildings.to_local(map.to_global(map.map_to_local(cell)))
		for target in _footprint(option, cell):
			_occupied[target] = instance
			if scene_option.blocks_movement:
				_blocked[target] = true
		buildings.add_child(instance)
	HumanNavigation.generate(map, blocked_cells())
	_committing = false
	inventory.changed.emit()
	built.emit(option, cell)
	return true


func _footprint(option: BuildOption, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if option is SceneBuildOption:
		for offset in (option as SceneBuildOption).occupied_cells:
			if not cells.has(origin + offset):
				cells.append(origin + offset)
	else:
		cells.append(origin)
	return cells
