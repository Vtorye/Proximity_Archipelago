@abstract
class_name PathAlgorithm
extends RefCounted
## Contract for grid path search algorithms. Contains no search logic.
## Works only with grid cells: no world coordinates and no TileMapLayer.
## Subclasses override all three methods.


## Build internal state from the grid snapshot. Called at startup and after every
## map change. Replaces any previous state completely.
@abstract func build(grid: TileGrid) -> void


## Return the cells from `from_cell` to `to_cell` inclusive,
## or an empty array if no path exists.
@abstract func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]


## Return the total cost of the least-cost path, or INF if no path exists.
## The start cell is not paid for; each subsequent cell pays its entry cost.
@abstract func get_cost(from_cell: Vector2i, to_cell: Vector2i) -> float

## Optional incremental update. Algorithms without mutable state can reuse build().
func update_grid(grid: TileGrid, _changed_cells: Array[Vector2i]) -> void:
	build(grid)
