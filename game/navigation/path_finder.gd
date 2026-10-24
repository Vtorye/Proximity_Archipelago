extends RefCounted
## Base interface for grid path search. Works only with grid cells.
## Subclasses implement build() and find_path().


## Replace the graph. `move_costs` maps every walkable Vector2i cell to its
## positive entry cost. Cells that are not keys are impassable.
func build(_move_costs: Dictionary) -> void:
	push_error("PathFinder.build() is not implemented.")


## Return the cells from `start` to `goal` inclusive, or an empty array if no path exists.
func find_path(_start: Vector2i, _goal: Vector2i) -> Array[Vector2i]:
	push_error("PathFinder.find_path() is not implemented.")
	var empty: Array[Vector2i] = []
	return empty
