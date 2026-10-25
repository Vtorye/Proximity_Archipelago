class_name TileGrid
extends RefCounted
## Snapshot of the navigable map. The only class that reads TileMapLayer and tile custom data.
## Algorithms query cells through this class and never touch the TileMapLayer.

var _rect := Rect2i()
var _costs := PackedFloat32Array()

## Replace the snapshot completely. Cells without a tile, with a non-positive
## `move_cost`, or listed in `blocked_cells` are not walkable.
func setup(map: TileMapLayer, blocked_cells: Array[Vector2i]) -> void:
	_rect = map.get_used_rect() if is_instance_valid(map) else Rect2i()
	_costs.resize(_rect.size.x * _rect.size.y)
	_costs.fill(0.0)
	if not is_instance_valid(map) or map.tile_set == null:
		return
	for cell in map.get_used_cells():
		var data: TileData = map.get_cell_tile_data(cell)
		if data != null:
			var value: Variant = data.get_custom_data("move_cost")
			if value is float or value is int:
				_costs[index(cell)] = maxf(0.0, float(value))
	for cell in blocked_cells:
		if in_bounds(cell):
			_costs[index(cell)] = 0.0

func configure(region: Rect2i, costs: PackedFloat32Array) -> void:
	assert(costs.size() == region.size.x * region.size.y)
	_rect = region
	_costs = costs.duplicate()

func index(cell: Vector2i) -> int:
	var local: Vector2i = cell - _rect.position
	return local.y * _rect.size.x + local.x

func cell_at(id: int) -> Vector2i:
	return _rect.position + Vector2i(id % _rect.size.x, id / _rect.size.x)

func size() -> Vector2i:
	return _rect.size

func rect() -> Rect2i:
	return _rect

func in_bounds(cell: Vector2i) -> bool:
	return _rect.has_point(cell)

func walkable(cell: Vector2i) -> bool:
	return in_bounds(cell) and _costs[index(cell)] > 0.0

## Cost of entering `cell`, or INF if it is not walkable.
func cost(cell: Vector2i) -> float:
	return _costs[index(cell)] if walkable(cell) else INF

## All walkable cells, in no particular order.
func walkable_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for id in range(_costs.size()):
		if _costs[id] > 0.0:
			cells.append(cell_at(id))
	return cells

## Walkable 4-neighbours of `cell`.
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var candidate: Vector2i = cell + offset
		if walkable(candidate):
			result.append(candidate)
	return result

func packed_costs() -> PackedFloat32Array:
	# Packed arrays use copy-on-write; a caller cannot mutate this snapshot through the returned value.
	return _costs

func with_cost(cell: Vector2i, value: float) -> TileGrid:
	var changed: PackedFloat32Array = _costs.duplicate()
	if in_bounds(cell):
		changed[index(cell)] = maxf(0.0, value)
	var result := TileGrid.new()
	result.configure(_rect, changed)
	return result
