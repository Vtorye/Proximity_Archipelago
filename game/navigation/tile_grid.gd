class_name TileGrid
extends RefCounted
## Snapshot of the navigable map. The only class that reads TileMapLayer and tile custom data.
## Algorithms query cells through this class and never touch the TileMapLayer.

var _rect := Rect2i()
var _costs: Dictionary = {} # Vector2i -> float, walkable cells only


## Replace the snapshot completely. Cells without a tile, with a non-positive
## `move_cost`, or listed in `blocked_cells` are not walkable.
func setup(map: TileMapLayer, blocked_cells: Array[Vector2i]) -> void:
	_rect = Rect2i()
	_costs.clear()
	if not is_instance_valid(map) or map.tile_set == null:
		return

	_rect = map.get_used_rect()

	var blocked: Dictionary = {}
	for cell in blocked_cells:
		blocked[cell] = true

	for cell in map.get_used_cells():
		if blocked.has(cell):
			continue
		var tile_data := map.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		var cost_value: Variant = tile_data.get_custom_data("move_cost")
		var move_cost := float(cost_value) if cost_value is float or cost_value is int else 0.0
		if move_cost > 0.0:
			_costs[cell] = move_cost


func size() -> Vector2i:
	return _rect.size


func rect() -> Rect2i:
	return _rect


func in_bounds(cell: Vector2i) -> bool:
	return _rect.has_point(cell)


func walkable(cell: Vector2i) -> bool:
	return _costs.has(cell)


## Cost of entering `cell`, or INF if it is not walkable.
func cost(cell: Vector2i) -> float:
	return float(_costs.get(cell, INF))


## All walkable cells, in no particular order.
func walkable_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _costs:
		result.append(cell)
	return result


## Walkable 4-neighbours of `cell`.
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var candidate: Vector2i = cell + offset
		if walkable(candidate):
			result.append(candidate)
	return result
