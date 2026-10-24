class_name RouteService
extends Node
## Owns a private navigation instance and serves cell-based routes.

signal navigation_changed

var _map: TileMapLayer
var _nav: Node


func setup(map: TileMapLayer) -> void:
	_map = map
	_nav = load("res://game/human_navigation.gd").new()
	add_child(_nav)
	_nav.navigation_changed.connect(_on_nav_changed)


func rebuild(blocked_cells: Array[Vector2i] = []) -> void:
	_nav.generate(_map, blocked_cells)


func cell_to_world(cell: Vector2i) -> Vector2:
	return _map.to_global(_map.map_to_local(cell))


func world_to_cell(world: Vector2) -> Vector2i:
	return _map.local_to_map(_map.to_local(world))


## Cost is in move_cost units, not seconds.
func get_path_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	return _nav.get_path_cost(from_cell, to_cell)


func request_route(from_cell: Vector2i, to_cell: Vector2i) -> Route:
	var cells: Array[Vector2i] = _nav.find_path(from_cell, to_cell)
	if cells.is_empty():
		return Route.invalid()

	var route := Route.new()
	route.cells = cells
	route.current_index = 0
	return route


func _on_nav_changed() -> void:
	navigation_changed.emit()
