extends "res://game/navigation/path_finder.gd"
## Dijkstra search over a 4-neighbour grid.
## Simple version: the frontier is a plain array scanned for the minimum.
## Each step pays the cost of the destination cell, the same as the A* version.

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]

var _move_costs: Dictionary = {}


func build(move_costs: Dictionary) -> void:
	_move_costs = move_costs.duplicate()


func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _move_costs.has(start) or not _move_costs.has(goal):
		return result

	var distance: Dictionary = {start: 0.0}
	var came_from: Dictionary = {}
	var settled: Dictionary = {}
	var frontier: Array[Vector2i] = [start]

	while not frontier.is_empty():
		# Take the frontier cell with the smallest known distance.
		var best_index := 0
		for index in range(1, frontier.size()):
			if distance[frontier[index]] < distance[frontier[best_index]]:
				best_index = index
		var current: Vector2i = frontier[best_index]
		frontier.remove_at(best_index)
		settled[current] = true

		if current == goal:
			return _reconstruct_path(came_from, goal)

		for offset in NEIGHBOURS:
			var next: Vector2i = current + offset
			if not _move_costs.has(next) or settled.has(next):
				continue

			var candidate: float = distance[current] + float(_move_costs[next])
			if not distance.has(next) or candidate < distance[next]:
				distance[next] = candidate
				came_from[next] = current
				if not frontier.has(next):
					frontier.append(next)

	return result


func _reconstruct_path(came_from: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var cell := goal
	while came_from.has(cell):
		cell = came_from[cell]
		path.push_front(cell)
	return path
