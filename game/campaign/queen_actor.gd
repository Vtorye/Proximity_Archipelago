class_name QueenActor
extends Node2D

signal arrived
signal died
@export_range(1, 100, 1) var maximum_health := 12
@export_range(1.0, 80.0, 1.0) var speed := 9.0
@onready var _health_bar: ProgressBar = %Health
var health: int:
	set(value):
		health = clampi(value, 0, maximum_health)
		if is_instance_valid(_health_bar):
			_health_bar.value = health
var navigation: RouteService
var map: TerrainMap
var walking := false
var goal := Vector2i.ZERO
var _revision := -1
var _route := PackedVector2Array()
var _index := 0
var _cached_origin := TileGrid.NO_CELL
var _cached_target := TileGrid.NO_CELL
var _cached_revision := -1
var _cached_path := PackedVector2Array()

func _ready() -> void:
	_health_bar.max_value = maximum_health
	health = maximum_health

func route_to(target: Vector2i) -> PackedVector2Array:
	if map == null or navigation == null:
		return PackedVector2Array()
	var origin := navigation.world_to_cell(global_position)
	if origin == _cached_origin and target == _cached_target and _cached_revision == navigation.revision:
		return _cached_path.duplicate()
	var cells: Dictionary[Vector2i, float] = {}
	for cell in map.get_used_cells():
		var surface := map.surface_at(cell)
		if surface != null and surface.kind == TerrainType.Kind.ROAD and navigation.walkable(cell):
			cells[cell] = surface.move_cost
	var grid := TileGrid.new()
	grid.configure_sparse(map.get_used_rect(), cells)
	var algorithm := preload("res://game/navigation/astar_path_finder.gd").new()
	algorithm.build(grid)
	var route: Array[Vector2i] = algorithm.find_path(origin, target)
	var points := PackedVector2Array()
	for cell in route:
		points.append(navigation.cell_to_world(cell))
	_cached_origin = origin
	_cached_target = target
	_cached_revision = navigation.revision
	_cached_path = points
	return points

func depart(target: Vector2i) -> bool:
	_route = route_to(target)
	if _route.is_empty() or health <= 0:
		return false
	goal = target
	walking = true
	_revision = navigation.revision
	_index = 0
	return true

func take_damage(amount: int) -> void:
	if health <= 0 or amount <= 0:
		return
	health -= amount
	if health == 0:
		walking = false
		died.emit()

func _physics_process(delta: float) -> void:
	if not walking or health <= 0:
		return
	if _revision != navigation.revision:
		_route = route_to(goal)
		_revision = navigation.revision
		_index = 0
	if _route.is_empty():
		return
	global_position = global_position.move_toward(_route[_index], speed * delta)
	if global_position.distance_squared_to(_route[_index]) < 0.01:
		_index += 1
		if _index == _route.size():
			walking = false
			arrived.emit()

