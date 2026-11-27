class_name GridSearch
extends RefCounted

const TIMING := preload("res://game/navigation/navigation_timing.gd")
## Dijkstra with a binary min-heap. No per-cell Dictionary or Node allocations.

static func build(grid: TileGrid, seeds: Array[Vector2i], reverse: bool = false, stop: Vector2i = TileGrid.NO_CELL) -> NavigationField:
	if not TIMING.enabled: return _build(grid, seeds, reverse, stop)
	TIMING.begin(&"dijkstra")
	var result := _build(grid, seeds, reverse, stop)
	TIMING.end()
	return result

static func _build(grid: TileGrid, seeds: Array[Vector2i], reverse: bool = false, stop: Vector2i = TileGrid.NO_CELL) -> NavigationField:
	var field := NavigationField.new()
	field.setup(grid, seeds, reverse)
	if field.costs.is_empty(): return field
	var terrain: PackedFloat32Array = grid.packed_costs()
	var adjacency: PackedInt32Array = grid.packed_neighbors()
	var heap: Array[Vector2] = []
	var settled := PackedByteArray()
	settled.resize(field.costs.size())
	for seed in seeds:
		if grid.walkable(seed):
			field.costs[field.index(seed)] = 0.0
			_push(heap, Vector2(0.0, grid.index(seed)))
	var stop_id: int = grid.index(stop)
	var track_seed := not field.seed_nodes.is_empty()
	if track_seed:
		for seed in seeds:
			if grid.walkable(seed): field.seed_nodes[field.index(seed)] = grid.index(seed)
	while not heap.is_empty():
		var item: Vector2 = _pop(heap)
		var id: int = int(item.y)
		var current: int = field.node_index(id)
		var offset: int = current - id
		# Equal heap entries can survive the float32 cost comparison after rounding.
		if settled[current] or item.x > field.costs[current]: continue
		settled[current] = 1
		if id == stop_id: break
		for direction in range(4):
			var next: int = adjacency[id * 4 + direction]
			if next < 0: continue
			# Reverse traversal preserves the original destination-entry edge weight.
			var step: float = terrain[id] if reverse else terrain[next]
			var candidate: float = field.costs[current] + step
			var target: int = next + offset
			if not settled[target] and candidate < field.costs[target]:
				field.costs[target] = candidate
				field.parents[target] = direction ^ 1
				if track_seed: field.seed_nodes[target] = field.seed_nodes[current]
				_push(heap, Vector2(candidate, next))
	return field

## Repair a complete field after entry costs went down on an unchanged graph.
## Only paths reachable through a cheaper edge can improve.
static func repair(field: NavigationField, grid: TileGrid, cheaper_nodes: PackedInt32Array) -> int:
	if TIMING.enabled: TIMING.begin(&"road_field_repair")
	field.use_cost_snapshot(grid)
	var updated := _repair(field, grid, cheaper_nodes)
	if TIMING.enabled: TIMING.end()
	return updated

static func _repair(field: NavigationField, grid: TileGrid, cheaper_nodes: PackedInt32Array) -> int:
	var terrain := grid.packed_costs()
	var adjacency := grid.packed_neighbors()
	var costs := field.costs
	var parents := field.parents
	var seed_nodes := field.seed_nodes
	var reverse := field.reverse
	var track_seed := not seed_nodes.is_empty()
	var heap: Array[Vector2] = []
	for id in cheaper_nodes:
		var index: int = field.node_index(id)
		if index < 0: continue
		var offset := index - id
		if reverse:
			# A cheaper entry into id is a cheaper edge out of id in the reversed graph.
			_push(heap, Vector2(costs[index], id))
			continue
		var best := Vector2(costs[index], id)
		var parent: int = parents[index]
		for direction in range(4):
			var neighbor: int = adjacency[id * 4 + direction]
			if neighbor < 0: continue
			var candidate := Vector2(costs[neighbor + offset] + terrain[id], id)
			if candidate.x < best.x:
				best = candidate
				parent = direction
		if best.x < costs[index]:
			costs[index] = best.x
			parents[index] = parent
			_push(heap, best)
	var visited := 0
	while not heap.is_empty():
		var item: Vector2 = _pop(heap)
		var id: int = int(item.y)
		var index: int = field.node_index(id)
		if item.x != costs[index]: continue
		visited += 1
		var offset := index - id
		for direction in range(4):
			var next: int = adjacency[id * 4 + direction]
			if next < 0: continue
			var target := next + offset
			var step: float = terrain[id] if reverse else terrain[next]
			var candidate := Vector2(item.x + step, next)
			if candidate.x < costs[target]:
				costs[target] = candidate.x
				parents[target] = direction ^ 1
				if track_seed: seed_nodes[target] = seed_nodes[index]
				_push(heap, candidate)
			elif track_seed and parents[target] == (direction ^ 1) and seed_nodes[target] != seed_nodes[index]:
				# A rounded distance can stay equal even when its parent changes goal.
				seed_nodes[target] = seed_nodes[index]
				_push(heap, Vector2(costs[target], next))
	return visited

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
