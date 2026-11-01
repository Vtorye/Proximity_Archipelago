class_name GridSearch
extends RefCounted
## Dijkstra with a binary min-heap. No per-cell Dictionary or Node allocations.

static func build(grid: TileGrid, seeds: Array[Vector2i], reverse: bool = false, stop: Vector2i = Vector2i(2147483647, 2147483647)) -> NavigationField:
	var field := NavigationField.new()
	field.setup(grid, seeds, reverse)
	if field.costs.is_empty(): return field
	var terrain: PackedFloat32Array = grid.packed_costs()
	var adjacency: PackedInt32Array = grid.packed_neighbors()
	var heap: Array[Vector2] = []
	for seed in seeds:
		if grid.walkable(seed):
			field.costs[field.index(seed)] = 0.0
			_push(heap, Vector2(0.0, grid.index(seed)))
	var stop_id: int = grid.index(stop)
	while not heap.is_empty():
		var item: Vector2 = _pop(heap)
		var id: int = int(item.y)
		var current: int = field.node_index(id)
		var offset: int = current - id
		if item.x > field.costs[current]: continue
		if id == stop_id: break
		for direction in range(4):
			var next: int = adjacency[id * 4 + direction]
			if next < 0: continue
			# Reverse traversal preserves the original destination-entry edge weight.
			var step: float = terrain[id] if reverse else terrain[next]
			var candidate: float = field.costs[current] + step
			var target: int = next + offset
			if candidate < field.costs[target]:
				field.costs[target] = candidate
				field.parents[target] = direction ^ 1
				_push(heap, Vector2(candidate, next))
	return field

static func _push(heap: Array[Vector2], item: Vector2) -> void:
	heap.append(item)
	var child: int = heap.size() - 1
	while child > 0:
		var parent: int = (child - 1) / 2
		if heap[parent].x <= item.x:
			break
		heap[child] = heap[parent]
		child = parent
	heap[child] = item

static func _pop(heap: Array[Vector2]) -> Vector2:
	var first: Vector2 = heap[0]
	var last: Vector2 = heap.pop_back()
	if heap.is_empty():
		return first
	var parent := 0
	while parent * 2 + 1 < heap.size():
		var child: int = parent * 2 + 1
		if child + 1 < heap.size() and heap[child + 1].x < heap[child].x:
			child += 1
		if heap[child].x >= last.x:
			break
		heap[parent] = heap[child]
		parent = child
	heap[parent] = last
	return first
