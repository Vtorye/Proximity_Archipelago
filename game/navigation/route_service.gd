class_name RouteService
extends Node
## Owns the navigation snapshot and the path algorithm, and serves cell-based routes.

signal navigation_changed
signal food_sources_changed

const MAX_CACHED_FIELDS := 64
# Forward fields use one float32 and one parent byte per reachable cell.
const FORWARD_CACHE_BYTES := 1024 * 1024
var revision := 0
## Changes that prevent reusing an existing field. Road discounts keep this revision.
var field_epoch := 0
var search_count := 0
var cache_hits := 0
var field_repairs := 0
var repaired_nodes := 0
var last_changed: Array[Vector2i] = []
## Existing paths stay walkable and cost no more after this revision.
var last_change_only_cheaper := false
var _map: TileMapLayer
var _grid := TileGrid.new()
var _algorithm: PathAlgorithm
var _fields: Dictionary[Vector2i, NavigationField] = {}
var _order: Array[Vector2i] = []
var _food_cells: Array[Vector2i] = []
var _food_field: NavigationField
var _cheaper_nodes: Dictionary[int, int] = {}

func setup(map: TileMapLayer, algorithm: PathAlgorithm = null) -> void:
	_map = map
	_algorithm = algorithm if algorithm != null else preload("res://game/navigation/astar_path_finder.gd").new()

func rebuild(blocked_cells: Array[Vector2i] = []) -> void:
	var next := TileGrid.new()
	next.setup(_map, blocked_cells)
	last_changed.clear()
	for cell in next.walkable_cells():
		if not is_equal_approx(next.cost(cell), _grid.cost(cell)):
			last_changed.append(cell)
	for cell in _grid.walkable_cells():
		if not next.walkable(cell):
			last_changed.append(cell)
	if last_changed.is_empty() and revision > 0 and next.rect() == _grid.rect():
		return
	_grid = next
	_algorithm.build(_grid)
	last_change_only_cheaper = false
	revision += 1
	_invalidate_fields()
	navigation_changed.emit()

func configure_grid(grid: TileGrid, algorithm: PathAlgorithm = null) -> void:
	_grid = grid
	_algorithm = algorithm if algorithm != null else preload("res://game/navigation/astar_path_finder.gd").new()
	_algorithm.build(_grid)
	last_change_only_cheaper = false
	revision += 1
	_invalidate_fields()

func cell_to_world(cell: Vector2i) -> Vector2:
	return _map.to_global(_map.map_to_local(cell))

func world_to_cell(world: Vector2) -> Vector2i:
	return _map.local_to_map(_map.to_local(world))

func cell_size() -> float:
	return _map.to_global(_map.map_to_local(Vector2i.RIGHT)).distance_to(cell_to_world(Vector2i.ZERO)) if _map != null else 16.0

func walkable(cell: Vector2i) -> bool:
	return _grid.walkable(cell)

func entry_cost(cell: Vector2i) -> float:
	return _grid.cost(cell)

## Cost is in move_cost units, not seconds.
func get_path_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	if not _grid.connected(from_cell, to_cell): return INF
	if _fields.has(from_cell):
		return distances_from(from_cell).cost(to_cell)
	search_count += 1
	return _algorithm.get_cost(from_cell, to_cell)

func distances_from(cell: Vector2i, previous: NavigationField = null) -> NavigationField:
	if _fields.has(cell):
		_order.erase(cell)
		_order.append(cell)
		return _refresh_field(_fields[cell], [cell], false)
	var field: NavigationField = _refresh_field(previous, [cell], false)
	_fields[cell] = field
	_order.append(cell)
	var limit := clampi(FORWARD_CACHE_BYTES / maxi(1, _grid.node_count() * 5), 1, MAX_CACHED_FIELDS)
	if _order.size() > limit:
		_fields.erase(_order.pop_front())
	return field

func set_food_cells(cells: Array[Vector2i]) -> void:
	if cells != _food_cells:
		_food_cells = cells.duplicate()
		_food_field = null
		food_sources_changed.emit()

func food_field() -> NavigationField:
	_food_field = _refresh_field(_food_field, _food_cells, true)
	return _food_field

## A caller may retain a complete field for the same ordered goals.
func reverse_field(goals: Array[Vector2i], previous: NavigationField = null) -> NavigationField:
	return _refresh_field(previous, goals, true)

func _refresh_field(field: NavigationField, seeds: Array[Vector2i], reverse: bool) -> NavigationField:
	if field != null and field.revision >= field_epoch:
		cache_hits += 1
		if field.revision < revision:
			var changes := PackedInt32Array()
			for id in _cheaper_nodes:
				if _cheaper_nodes[id] > field.revision:
					changes.append(id)
			repaired_nodes += GridSearch.repair(field, _grid, changes)
			field_repairs += 1
			field.revision = revision
		return field
	search_count += 1
	field = GridSearch.build(_grid, seeds, reverse)
	field.revision = revision
	return field

func request_route(from_cell: Vector2i, to_cell: Vector2i) -> Route:
	if not _grid.connected(from_cell, to_cell): return make_route([])
	var cells: Array[Vector2i]
	if _fields.has(from_cell):
		cells = distances_from(from_cell).path(to_cell)
	else:
		search_count += 1
		cells = _algorithm.find_path(from_cell, to_cell)
	return make_route(cells)

func make_route(cells: Array[Vector2i]) -> Route:
	var route := Route.new()
	route.cells = cells
	route.revision = revision
	for index in range(1, cells.size()):
		route.cost += _grid.cost(cells[index])
	return route

func snapshot() -> TileGrid:
	return _grid

## Construction supplies its footprint, avoiding a full TileMap scan for each command.
func update_cells(cells: Array[Vector2i], blocked: Array[Vector2i]) -> void:
	var next: TileGrid = _grid.with_map_cells(_map, cells, blocked)
	if next.rect() != _grid.rect():
		rebuild(blocked)
		return
	last_changed.clear()
	for cell in cells:
		if not is_equal_approx(next.cost(cell), _grid.cost(cell)):
			last_changed.append(cell)
	if last_changed.is_empty():
		return
	last_change_only_cheaper = last_changed.all(func(cell: Vector2i) -> bool:
		return _grid.walkable(cell) and next.cost(cell) < _grid.cost(cell))
	_grid = next
	_algorithm.update_grid(_grid, last_changed)
	revision += 1
	if last_change_only_cheaper:
		for cell in last_changed:
			_cheaper_nodes[_grid.index(cell)] = revision
	else:
		_invalidate_fields()
	navigation_changed.emit()

func _invalidate_fields() -> void:
	field_epoch = revision
	_cheaper_nodes.clear()
	_fields.clear()
	_order.clear()
	_food_field = null
