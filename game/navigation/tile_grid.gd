class_name TileGrid
extends RefCounted
## Snapshot of the navigable map. The only class that reads TileMapLayer and tile custom data.
## Algorithms query cells through this class and never touch the TileMapLayer.
const OFFSETS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var _rect := Rect2i()
var _ids: Dictionary[Vector2i, int] = {}
var _cells: Array[Vector2i] = []
var _costs := PackedFloat32Array()
var _neighbors := PackedInt32Array()
var _components := PackedInt32Array()
var _starts := PackedInt32Array()
var _sizes := PackedInt32Array()

## Replace the snapshot completely. Cells without a tile, with a non-positive
## `move_cost`, or listed in `blocked_cells` are not walkable.
func setup(map: TileMapLayer, blocked_cells: Array[Vector2i]) -> void:
	var values: Dictionary[Vector2i, float] = {}
	var blocked: Dictionary[Vector2i, bool] = {}
	for cell in blocked_cells: blocked[cell] = true
	if is_instance_valid(map) and map.tile_set != null:
		for cell in map.get_used_cells():
			var value: float = _map_cost(map, cell) if not blocked.has(cell) else 0.0
			if value > 0.0: values[cell] = value
	configure_sparse(map.get_used_rect() if is_instance_valid(map) else Rect2i(), values)

## Dense fixtures remain accepted; runtime maps never allocate their bounding rectangle.
func configure(region: Rect2i, costs: PackedFloat32Array) -> void:
	assert(costs.size() == region.size.x * region.size.y)
	var values: Dictionary[Vector2i, float] = {}
	for id in range(costs.size()):
		if costs[id] > 0.0 and is_finite(costs[id]):
			values[region.position + Vector2i(id % region.size.x, id / region.size.x)] = costs[id]
	configure_sparse(region, values)

func configure_sparse(region: Rect2i, values: Dictionary[Vector2i, float]) -> void:
	_rect = region
	_ids.clear()
	_cells.clear()
	_starts.clear()
	_sizes.clear()
	# Group adjacent land into contiguous ranges. Fields share this immutable index.
	for seed in values:
		if _ids.has(seed) or not _valid(values[seed]) or not region.has_point(seed): continue
		var start: int = _cells.size()
		_ids[seed] = start
		_cells.append(seed)
		var cursor: int = start
		while cursor < _cells.size():
			var cell: Vector2i = _cells[cursor]
			for offset in OFFSETS:
				var next: Vector2i = cell + offset
				if not _ids.has(next) and region.has_point(next) and values.has(next) and _valid(values[next]):
					_ids[next] = _cells.size()
					_cells.append(next)
			cursor += 1
		_starts.append(start)
		_sizes.append(_cells.size() - start)
	_costs.resize(_cells.size())
	_components.resize(_cells.size())
	_neighbors.resize(_cells.size() * 4)
	_neighbors.fill(-1)
	for component in range(_starts.size()):
		for id in range(_starts[component], _starts[component] + _sizes[component]):
			_components[id] = component
			_costs[id] = values[_cells[id]]
			for direction in range(4): _neighbors[id * 4 + direction] = index(_cells[id] + OFFSETS[direction])

static func _valid(value: float) -> bool:
	return value > 0.0 and is_finite(value)

static func _map_cost(map: TileMapLayer, cell: Vector2i) -> float:
	var data: TileData = map.get_cell_tile_data(cell)
	if data == null: return 0.0
	if map.tile_set.get_custom_data_layer_by_name("walkable") >= 0 and not data.get_custom_data("walkable"): return 0.0
	var value: Variant = data.get_custom_data("move_cost")
	return float(value) if (value is float or value is int) and _valid(float(value)) else 0.0

func index(cell: Vector2i) -> int:
	return _ids.get(cell, -1)
func cell_at(id: int) -> Vector2i:
	return _cells[id]
func rect() -> Rect2i:
	return _rect
func in_bounds(cell: Vector2i) -> bool:
	return _rect.has_point(cell)
func walkable(cell: Vector2i) -> bool:
	return _ids.has(cell)
## Cost of entering `cell`, or INF if it is not walkable.
func cost(cell: Vector2i) -> float:
	var id: int = index(cell)
	return _costs[id] if id >= 0 else INF
## All walkable cells, in no particular order.
func walkable_cells() -> Array[Vector2i]:
	return _cells.duplicate()
## Walkable 4-neighbours of `cell`.
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var id: int = index(cell)
	if id >= 0:
		for direction in range(4):
			var next: int = neighbor_id(id, direction)
			if next >= 0: result.append(_cells[next])
	return result
func packed_costs() -> PackedFloat32Array:
	# Packed arrays use copy-on-write; a caller cannot mutate this snapshot through the returned value.
	return _costs
func packed_neighbors() -> PackedInt32Array:
	return _neighbors
func node_count() -> int:
	return _cells.size()
func component_count() -> int:
	return _starts.size()
func component(cell: Vector2i) -> int:
	var id: int = index(cell)
	return component_id(id) if id >= 0 else -1
func component_id(id: int) -> int:
	return _components[id]
func component_start(id: int) -> int:
	return _starts[id]
func component_size(id: int) -> int:
	return _sizes[id]
func connected(a: Vector2i, b: Vector2i) -> bool:
	return walkable(a) and walkable(b) and component(a) == component(b)
func neighbor_id(id: int, direction: int) -> int:
	return _neighbors[id * 4 + direction]
func node_cost(id: int) -> float:
	return _costs[id]
func with_cost(cell: Vector2i, value: float) -> TileGrid:
	return with_costs({cell: value})
## A construction plan copies the grid once, regardless of the number of painted cells.
func with_costs(values: Dictionary[Vector2i, float]) -> TileGrid:
	var changed: Dictionary[Vector2i, float] = {}
	for id in range(_cells.size()): changed[_cells[id]] = _costs[id]
	for cell in values:
		if not in_bounds(cell): continue
		if _valid(values[cell]): changed[cell] = values[cell]
		else: changed.erase(cell)
	var result := TileGrid.new()
	result.configure_sparse(_rect, changed)
	return result
## Copy only changed terrain values; readers keep their previous snapshot.
func with_map_cells(map: TileMapLayer, cells: Array[Vector2i], blocked: Array[Vector2i]) -> TileGrid:
	if map.get_used_rect() != _rect:
		var result := TileGrid.new()
		result.setup(map, blocked)
		return result
	var values: Dictionary[Vector2i, float] = {}
	for cell in cells: values[cell] = 0.0 if blocked.has(cell) else _map_cost(map, cell)
	return with_costs(values)
