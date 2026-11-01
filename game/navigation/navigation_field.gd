class_name NavigationField
extends RefCounted
## A shared shortest-path tree. A byte per cell encodes its parent direction.
## Only seeded components allocate distances; water and unrelated islands allocate nothing.
var costs := PackedFloat32Array()
var parents := PackedByteArray()
var reverse := false
var _grid: TileGrid
var _offsets: Dictionary[int, int] = {}
func setup(grid: TileGrid, seeds: Array[Vector2i], backwards: bool) -> void:
	_grid = grid
	reverse = backwards
	var count := 0
	for seed in seeds:
		var component: int = grid.component(seed)
		if component < 0 or _offsets.has(component): continue
		_offsets[component] = count - grid.component_start(component)
		count += grid.component_size(component)
	costs.resize(count)
	costs.fill(INF)
	parents.resize(count)
	parents.fill(255)
func node_index(id: int) -> int:
	var component: int = _grid.component_id(id)
	return id + _offsets[component] if _offsets.has(component) else -1
func index(cell: Vector2i) -> int:
	var id: int = _grid.index(cell)
	return node_index(id) if id >= 0 else -1
func cost(cell: Vector2i) -> float:
	var id: int = index(cell)
	return costs[id] if id >= 0 else INF
func path(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_finite(cost(cell)): return result
	while result.size() <= costs.size():
		result.append(cell)
		var direction: int = parents[index(cell)]
		if direction == 255: break
		cell += TileGrid.OFFSETS[direction]
	if not reverse: result.reverse()
	return result
