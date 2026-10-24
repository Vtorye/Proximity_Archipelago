extends "res://game/navigation/path_algorithm.gd"
## Dijkstra search over a 4-neighbour grid.
## Simple version: the frontier is a plain array scanned for the minimum.
## Each step pays the entry cost of the destination cell, the same as the A* version.

var _costs: Dictionary = {} # Vector2i -> float, copied from the grid in build()


func build(grid: TileGrid) -> void:
	_costs.clear()
	for cell in grid.walkable_cells():
		_costs[cell] = grid.cost(cell)


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _costs.has(from_cell) or not _costs.has(to_cell):
		return result

	var distance: Dictionary = {from_cell: 0.0}
	var came_from: Dictionary = {}
	var settled: Dictionary = {}
	var frontier: Array[Vector2i] = [from_cell]

	while not frontier.is_empty():
		# Take the frontier cell with the smallest known distance.
		var best_index := 0
		for index in range(1, frontier.size()):
			if distance[frontier[index]] < distance[frontier[best_index]]:
				best_index = index
		var current: Vector2i = frontier[best_index]
		frontier.remove_at(best_index)
		settled[current] = true

		if current == to_cell:
			return _reconstruct_path(came_from, to_cell)

		for next in _neighbors(current):
			if settled.has(next):
				continue

			var candidate: float = distance[current] + float(_costs[next])
			if not distance.has(next) or candidate < distance[next]:
				distance[next] = candidate
				came_from[next] = current
				if not frontier.has(next):
					frontier.append(next)

	return result


func get_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var path := find_path(from_cell, to_cell)
	if path.is_empty():
		return INF

	var total := 0.0
	for index in range(1, path.size()):
		total += float(_costs[path[index]])
	return total


func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var candidate: Vector2i = cell + offset
		if _costs.has(candidate):
			result.append(candidate)
	return result


func _reconstruct_path(came_from: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var cell := goal
	while came_from.has(cell):
		cell = came_from[cell]
		path.push_front(cell)
	return path
