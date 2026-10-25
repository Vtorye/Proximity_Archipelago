class_name RouteService
extends Node
## Owns the navigation snapshot and the path algorithm, and serves cell-based routes.

signal navigation_changed
signal food_sources_changed

const MAX_CACHED_FIELDS := 8
var revision := 0
var search_count := 0
var cache_hits := 0
var last_changed: Array[Vector2i] = []
var _map: TileMapLayer
var _grid := TileGrid.new()
var _algorithm: PathAlgorithm
var _fields: Dictionary[Vector2i, NavigationField] = {}
var _order: Array[Vector2i] = []
var _food_cells: Array[Vector2i] = []
var _food_field: NavigationField

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
	revision += 1
	_fields.clear()
	_order.clear()
	_food_field = null
	navigation_changed.emit()

func configure_grid(grid: TileGrid, algorithm: PathAlgorithm = null) -> void:
	_grid = grid
	_algorithm = algorithm if algorithm != null else preload("res://game/navigation/astar_path_finder.gd").new()
	_algorithm.build(_grid)
	_fields.clear()
	_order.clear()
	_food_field = null
	revision += 1

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
	if _fields.has(from_cell):
		cache_hits += 1
		return _fields[from_cell].cost(to_cell)
	search_count += 1
	return _algorithm.get_cost(from_cell, to_cell)

func distances_from(cell: Vector2i) -> NavigationField:
	if _fields.has(cell):
		cache_hits += 1
		_order.erase(cell)
		_order.append(cell)
		return _fields[cell]
	search_count += 1
	var field: NavigationField = GridSearch.build(_grid, [cell])
	_fields[cell] = field
	_order.append(cell)
	if _order.size() > MAX_CACHED_FIELDS:
		_fields.erase(_order.pop_front())
	return field

func set_food_cells(cells: Array[Vector2i]) -> void:
	if cells != _food_cells:
		_food_cells = cells.duplicate()
		_food_field = null
		food_sources_changed.emit()

func food_field() -> NavigationField:
	if _food_field == null:
		search_count += 1
		_food_field = GridSearch.build(_grid, _food_cells, true)
	return _food_field

func reverse_field(goals: Array[Vector2i]) -> NavigationField:
	search_count += 1
	return GridSearch.build(_grid, goals, true)

func request_route(from_cell: Vector2i, to_cell: Vector2i) -> Route:
	var cells: Array[Vector2i]
	if _fields.has(from_cell):
		cells = _fields[from_cell].path(to_cell)
		cache_hits += 1
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

func route_affected(route: Route) -> bool:
	if route == null:
		return false
	for index in range(route.current_index, route.cells.size()):
		if route.cells[index] in last_changed:
			return true
	return false

func snapshot() -> TileGrid:
	return _grid

func is_food_cell(cell: Vector2i) -> bool:
	return _food_cells.has(cell)
