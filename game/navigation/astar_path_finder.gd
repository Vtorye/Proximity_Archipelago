extends "res://game/navigation/path_algorithm.gd"

const TIMING := preload("res://game/navigation/navigation_timing.gd")
## A* over a 4-neighbour graph. Water has no AStar2D point.
var _astar := AStar2D.new()
var _grid: TileGrid
var _dirty := true
func build(grid: TileGrid) -> void:
	_grid = grid
	_dirty = true

func _prepare_graph() -> void:
	if not TIMING.enabled:
		_prepare_graph_inner()
		return
	TIMING.begin(&"astar_graph")
	_prepare_graph_inner()
	TIMING.end()

func _prepare_graph_inner() -> void:
	if not _dirty: return
	_dirty = false
	_astar.clear()
	var grid := _grid
	if grid.node_count() == 0: return
	var minimum := INF
	for cost in grid.packed_costs(): minimum = minf(minimum, cost)
	for id in range(grid.node_count()):
		# Scale so the built-in distance heuristic stays admissible
		# even when the cheapest tile costs less than 1.
		_astar.add_point(id, Vector2(grid.cell_at(id)), grid.node_cost(id) / minimum)
	for id in range(grid.node_count()):
		for direction in [1, 3]:
			var next: int = grid.neighbor_id(id, direction)
			if next >= 0: _astar.connect_points(id, next)
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _grid.connected(from_cell, to_cell): return result
	_prepare_graph()
	for id in _astar.get_id_path(_grid.index(from_cell), _grid.index(to_cell)):
		result.append(_grid.cell_at(id))
	return result
func get_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var path: Array[Vector2i] = find_path(from_cell, to_cell)
	if path.is_empty(): return INF
	var total := 0.0
	for index in range(1, path.size()): total += _grid.cost(path[index])
	return total
