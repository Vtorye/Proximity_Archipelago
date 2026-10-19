extends Node
## Weighted grid navigation for Human agents.

signal navigation_changed

var _map: TileMapLayer
var _astar := AStarGrid2D.new()
var _move_costs: Dictionary = {}


## Rebuild the navigation grid from the supplied TileMapLayer.
## Tiles with a positive `move_cost` are traversable; all other cells are blocked.
func generate(map: TileMapLayer, blocked_cells: Array[Vector2i] = []) -> void:
	_map = map
	_move_costs.clear()
	_astar.clear()

	if not is_instance_valid(_map) or _map.tile_set == null:
		push_warning("HumanNavigation.generate() requires a TileMapLayer with a TileSet.")
		return

	var used_rect := _map.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return

	_astar.region = used_rect
	_astar.cell_size = _map.tile_set.tile_size
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

	# AStarGrid defaults to open cells, including holes in the map.
	_astar.fill_solid_region(used_rect, true)
	var minimum_move_cost := INF
	for cell in _map.get_used_cells():
		var tile_data := _map.get_cell_tile_data(cell)
		if tile_data == null:
			_astar.set_point_solid(cell, true)
			continue

		var cost_value: Variant = tile_data.get_custom_data("move_cost")
		var move_cost := float(cost_value) if cost_value is float or cost_value is int else 0.0
		if move_cost <= 0.0:
			_astar.set_point_solid(cell, true)
			continue

		if blocked_cells.has(cell):
			continue
		_astar.set_point_solid(cell, false)
		_move_costs[cell] = move_cost
		minimum_move_cost = minf(minimum_move_cost, move_cost)

	# Normalize scales so the built-in distance heuristic remains admissible
	# even when the cheapest tile costs less than 1.
	for cell in _move_costs:
		_astar.set_point_weight_scale(cell, float(_move_costs[cell]) / minimum_move_cost)

	navigation_changed.emit()


## Return the least-cost route from a world position to another as world positions.
## An empty array means the grid is uninitialized or no route exists.
func get_path_world_positions(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var start_cell := _world_to_cell(from_world)
	var end_cell := _world_to_cell(to_world)
	if not _is_walkable(start_cell) or not _is_walkable(end_cell):
		return PackedVector2Array()

	var cell_path := _astar.get_id_path(start_cell, end_cell)
	var world_path := PackedVector2Array()
	for cell in cell_path:
		world_path.append(_map.to_global(_map.map_to_local(cell)))
	return world_path


## Return the total weighted movement cost of the least-cost route.
## Returns INF when no route exists. Each step pays the destination tile's cost.
func get_path_cost(from_world: Vector2, to_world: Vector2) -> float:
	var start_cell := _world_to_cell(from_world)
	var end_cell := _world_to_cell(to_world)
	if not _is_walkable(start_cell) or not _is_walkable(end_cell):
		return INF

	var cell_path := _astar.get_id_path(start_cell, end_cell)
	if cell_path.is_empty():
		return INF

	var total_cost := 0.0
	for index in range(1, cell_path.size()):
		total_cost += float(_move_costs.get(cell_path[index], 0.0))
	return total_cost


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return _map.local_to_map(_map.to_local(world_position))


func _is_walkable(cell: Vector2i) -> bool:
	return is_instance_valid(_map) and _move_costs.has(cell) and not _astar.is_point_solid(cell)
