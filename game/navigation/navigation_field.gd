class_name NavigationField
extends RefCounted
## A shared shortest-path tree. A byte per cell encodes its parent direction.
## Only seeded components allocate distances; water and unrelated islands allocate nothing.
var costs := PackedFloat32Array()
var parents := PackedByteArray()
var seed_nodes := PackedInt32Array()
var reverse := false
## Revision assigned by RouteService to a complete cached field.
var revision := -1
var _grid: TileGrid
var _offsets: Dictionary[int, int] = {}
var _single_seed: Vector2i
func setup(grid: TileGrid, seeds: Array[Vector2i], backwards: bool) -> void:
	_grid = grid
	reverse = backwards
	var count := 0
	for seed in seeds:
		var component: int = grid.component(seed)
		if component >= 0: _single_seed = seed
		if component < 0 or _offsets.has(component): continue
		_offsets[component] = count - grid.component_start(component)
		count += grid.component_size(component)
	costs.resize(count)
	costs.fill(INF)
	parents.resize(count)
	parents.fill(255)
	if reverse and seeds.size() > 1:
		seed_nodes.resize(count)
func node_index(id: int) -> int:
	var component: int = _grid.component_id(id)
	return id + _offsets[component] if _offsets.has(component) else -1

## Cost-only edits preserve IDs, neighbors, and component storage.
func use_cost_snapshot(grid: TileGrid) -> void:
	_grid = grid
func index(cell: Vector2i) -> int:
	var id: int = _grid.index(cell)
	return node_index(id) if id >= 0 else -1
func cost(cell: Vector2i) -> float:
	return cost_at_node(_grid.index(cell))
## Reads a node ID from the same grid snapshot as this field.
func cost_at_node(node_id: int) -> float:
	var id: int = node_index(node_id) if node_id >= 0 else -1
	return costs[id] if id >= 0 else INF

## Returns the endpoint for a reachable cell in a reverse field.
func destination(cell: Vector2i) -> Vector2i:
	assert(reverse and is_finite(cost(cell)))
	return _single_seed if seed_nodes.is_empty() else _grid.cell_at(seed_nodes[index(cell)])

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
