extends "res://game/navigation/path_algorithm.gd"
## Dijkstra search over a 4-neighbour grid.
## A binary heap selects the frontier minimum without scanning an array.
## Each step pays the entry cost of the destination cell, the same as the A* version.

var _grid: TileGrid

func build(grid: TileGrid) -> void:
	_grid = grid

func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not _grid.walkable(from_cell) or not _grid.walkable(to_cell):
		return []
	return GridSearch.build(_grid, [from_cell], false, to_cell).path(to_cell)

func get_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	if not _grid.walkable(from_cell) or not _grid.walkable(to_cell):
		return INF
	return GridSearch.build(_grid, [from_cell], false, to_cell).cost(to_cell)
