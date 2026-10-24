class_name PathAlgorithm
extends RefCounted
## Contract for grid path search algorithms. Contains no search logic.
## Works only with grid cells: no world coordinates and no TileMapLayer.
## Subclasses override all three methods.


## Build internal state from the grid snapshot. Called at startup and after every
## map change. Replaces any previous state completely.
func build(_grid: TileGrid) -> void:
	push_error("PathAlgorithm.build() is not implemented.")


## Return the cells from `from_cell` to `to_cell` inclusive,
## or an empty array if no path exists.
func find_path(_from_cell: Vector2i, _to_cell: Vector2i) -> Array[Vector2i]:
	push_error("PathAlgorithm.find_path() is not implemented.")
	var empty: Array[Vector2i] = []
	return empty


## Return the total cost of the least-cost path, or INF if no path exists.
## The start cell is not paid for; each subsequent cell pays its entry cost.
func get_cost(_from_cell: Vector2i, _to_cell: Vector2i) -> float:
	push_error("PathAlgorithm.get_cost() is not implemented.")
	return INF
