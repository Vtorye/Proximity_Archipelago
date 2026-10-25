class_name GridSearch
extends RefCounted
## Dijkstra with a binary min-heap. No per-cell Dictionary or Node allocations.

static func build(grid: TileGrid, seeds: Array[Vector2i], reverse: bool = false, stop: Vector2i = Vector2i(2147483647, 2147483647)) -> NavigationField:
	var field := NavigationField.new()
	field.region = grid.rect()
	field.reverse = reverse
	var width: int = field.region.size.x
	var count: int = width * field.region.size.y
	var terrain: PackedFloat32Array = grid.packed_costs()
	var distances := PackedFloat32Array()
	distances.resize(count)
	distances.fill(INF)
	var parents := PackedByteArray()
	parents.resize(count)
	parents.fill(255)
	var heap: Array[Vector2] = []
	for seed in seeds:
		if grid.walkable(seed):
			var id: int = grid.index(seed)
			distances[id] = 0.0
			_push(heap, Vector2(0.0, id))
	var stop_id: int = grid.index(stop) if grid.in_bounds(stop) else -1
	while not heap.is_empty():
		var item: Vector2 = _pop(heap)
		var id: int = int(item.y)
		if item.x > distances[id]:
			continue
		if id == stop_id:
			break
		var column: int = id % width
		for direction in range(4):
			var next: int = id
			match direction:
				0:
					if column == 0: continue
					next -= 1
				1:
					if column == width - 1: continue
					next += 1
				2: next -= width
				3: next += width
			if next < 0 or next >= count or terrain[next] <= 0.0:
				continue
			# Reverse traversal preserves the original destination-entry edge weight.
			var step: float = terrain[id] if reverse else terrain[next]
			var candidate: float = distances[id] + step
			if candidate < distances[next]:
				distances[next] = candidate
				parents[next] = direction ^ 1
				_push(heap, Vector2(candidate, next))
	field.costs = distances
	field.parents = parents
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
