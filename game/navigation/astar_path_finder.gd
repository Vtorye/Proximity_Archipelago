extends "res://game/navigation/path_finder.gd"
## A* search over a 4-neighbour grid, backed by AStarGrid2D.

var _astar := AStarGrid2D.new()


func build(move_costs: Dictionary) -> void:
	_astar.clear()
	if move_costs.is_empty():
		return

	var min_cell := Vector2i(move_costs.keys()[0])
	var max_cell := min_cell
	var min_cost := INF
	for cell in move_costs:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
		min_cost = minf(min_cost, float(move_costs[cell]))

	var region := Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)
	_astar.region = region
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

	# AStarGrid2D defaults to open cells, so close everything first.
	_astar.fill_solid_region(region, true)
	for cell in move_costs:
		_astar.set_point_solid(cell, false)
		# Scale so the built-in distance heuristic stays admissible
		# even when the cheapest tile costs less than 1.
		_astar.set_point_weight_scale(cell, float(move_costs[cell]) / min_cost)


func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _astar.is_in_boundsv(start) or not _astar.is_in_boundsv(goal):
		return result
	if _astar.is_point_solid(start) or _astar.is_point_solid(goal):
		return result

	for cell in _astar.get_id_path(start, goal):
		result.append(Vector2i(cell))
	return result
