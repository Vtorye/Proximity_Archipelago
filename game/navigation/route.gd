class_name Route
extends RefCounted

var cells: Array[Vector2i] = []
var current_index: int = 0


static func invalid() -> Route:
	return Route.new()


func is_valid() -> bool:
	return not cells.is_empty()


func is_finished() -> bool:
	if not is_valid():
		return false
	return current_index >= cells.size() - 1


func current_cell() -> Vector2i:
	if not is_valid():
		return Vector2i.ZERO
	var index := clampi(current_index, 0, cells.size() - 1)
	return cells[index]


func next_cell() -> Vector2i:
	var next_index := current_index + 1
	if next_index >= 0 and next_index < cells.size():
		return cells[next_index]
	return current_cell()


func advance() -> void:
	if not is_finished():
		current_index += 1
