extends "res://game/navigation/path_algorithm.gd"
## A* over a 4-neighbour grid, backed by AStarGrid2D.

var _astar := AStarGrid2D.new()
var _costs: Dictionary = {} # Vector2i -> float, copied from the grid in build()


func build(grid: TileGrid) -> void:
	_astar.clear()
	_costs.clear()

	var cells := grid.walkable_cells()
	var rect := grid.rect()
	if cells.is_empty() or rect.size == Vector2i.ZERO:
		return

	var min_cost := INF
	for cell in cells:
		var move_cost := grid.cost(cell)
		_costs[cell] = move_cost
		min_cost = minf(min_cost, move_cost)

	_astar.region = rect
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()

	# AStarGrid2D defaults to open cells, so close everything first.
	_astar.fill_solid_region(rect, true)
	for cell in cells:
		_astar.set_point_solid(cell, false)
		# Scale so the built-in distance heuristic stays admissible
		# even when the cheapest tile costs less than 1.
		_astar.set_point_weight_scale(cell, float(_costs[cell]) / min_cost)


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _costs.has(from_cell) or not _costs.has(to_cell):
		return result

	for cell in _astar.get_id_path(from_cell, to_cell):
		result.append(Vector2i(cell))
	return result


func get_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var path := find_path(from_cell, to_cell)
	if path.is_empty():
		return INF

	var total := 0.0
	for index in range(1, path.size()):
		total += float(_costs[path[index]])
	return total
