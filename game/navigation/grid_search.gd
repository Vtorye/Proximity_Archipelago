class_name GridSearch
extends RefCounted
## Dijkstra with a binary min-heap. No per-cell Dictionary or Node allocations.

static func build(grid: TileGrid, seeds: Array[Vector2i], reverse: bool = false, stop: Vector2i = Vector2i(2147483647, 2147483647)) -> NavigationField:
	var field := NavigationField.new()
	field.region = grid.rect()
	field.reverse = reverse
	var count: int = field.region.size.x * field.region.size.y
	field.costs.resize(count)
	field.costs.fill(INF)
	field.parents.resize(count)
	field.parents.fill(-1)
	field.goal_ids.resize(count)
	field.goal_ids.fill(-1)
	var heap: Array[Vector2] = []
	for seed_id in range(seeds.size()):
		var seed: Vector2i = seeds[seed_id]
		if grid.walkable(seed):
			var id: int = grid.index(seed)
			field.costs[id] = 0.0
			field.goal_ids[id] = seed_id
			_push(heap, Vector2(0.0, id))
	while not heap.is_empty():
		var item: Vector2 = _pop(heap)
		var id: int = int(item.y)
		if item.x > field.costs[id]:
			continue
		var cell: Vector2i = grid.cell_at(id)
		if cell == stop:
			break
		for neighbor in grid.neighbors(cell):
			var next: int = grid.index(neighbor)
			# Reverse traversal preserves the original destination-entry edge weight.
			var step: float = grid.cost(cell) if reverse else grid.cost(neighbor)
			var candidate: float = field.costs[id] + step
			if candidate < field.costs[next]:
				field.costs[next] = candidate
				field.parents[next] = id
				field.goal_ids[next] = field.goal_ids[id]
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
