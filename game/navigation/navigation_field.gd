class_name NavigationField
extends RefCounted
## A shared shortest-path tree. A byte per cell encodes its parent direction.
var region: Rect2i
var costs := PackedFloat32Array()
var parents := PackedByteArray()
var reverse := false

func index(cell: Vector2i) -> int:
	var local: Vector2i = cell - region.position
	return local.y * region.size.x + local.x

func cell_at(id: int) -> Vector2i:
	return region.position + Vector2i(id % region.size.x, id / region.size.x)

func cost(cell: Vector2i) -> float:
	return costs[index(cell)] if region.has_point(cell) else INF

func path(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_finite(cost(cell)):
		return result
	var id: int = index(cell)
	while result.size() <= costs.size():
		result.append(cell_at(id))
		match parents[id]:
			0: id -= 1
			1: id += 1
			2: id -= region.size.x
			3: id += region.size.x
			_: break
	if not reverse:
		result.reverse()
	return result
