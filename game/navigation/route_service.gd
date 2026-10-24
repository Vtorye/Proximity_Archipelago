class_name RouteService
extends Node
## Owns the navigation snapshot and the path algorithm, and serves cell-based routes.

signal navigation_changed

## Path algorithm used for routing. Swap the script path here to change algorithm.
const ALGORITHM_SCRIPT := "res://game/navigation/dijkstra_path_finder.gd" # A*: "res://game/navigation/astar_path_finder.gd"

var _map: TileMapLayer
var _grid := TileGrid.new()
var _algorithm: PathAlgorithm


func setup(map: TileMapLayer) -> void:
	_map = map
	_algorithm = load(ALGORITHM_SCRIPT).new()


func rebuild(blocked_cells: Array[Vector2i] = []) -> void:
	_grid.setup(_map, blocked_cells)
	_algorithm.build(_grid)
	navigation_changed.emit()


func cell_to_world(cell: Vector2i) -> Vector2:
	return _map.to_global(_map.map_to_local(cell))


func world_to_cell(world: Vector2) -> Vector2i:
	return _map.local_to_map(_map.to_local(world))


## Cost is in move_cost units, not seconds.
func get_path_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	return _algorithm.get_cost(from_cell, to_cell)


func request_route(from_cell: Vector2i, to_cell: Vector2i) -> Route:
	var cells := _algorithm.find_path(from_cell, to_cell)
	if cells.is_empty():
		return Route.invalid()

	var route := Route.new()
	route.cells = cells
	route.current_index = 0
	return route
