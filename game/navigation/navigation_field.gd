class_name NavigationField
extends RefCounted
## A shared shortest-path tree. Reverse trees lead every cell toward a goal.

var region: Rect2i
var costs := PackedFloat32Array()
var parents := PackedInt32Array()
var goal_ids := PackedInt32Array()
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
	while id >= 0 and result.size() <= costs.size():
		result.append(cell_at(id))
		id = parents[id]
	if not reverse:
		result.reverse()
	return result
