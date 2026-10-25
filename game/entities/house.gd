class_name House
extends Building

@export var capacity: int = 5
@export var human_scene: PackedScene

var _residents: Array[Node2D] = []
var residents: Array[Node2D]:
	get:
		_prune()
		return _residents.duplicate()


func has_space() -> bool:
	_prune()
	return _residents.size() < capacity


func add_resident(human: Node2D) -> bool:
	if not is_instance_valid(human) or _residents.has(human) or not has_space():
		return false
	_residents.append(human)
	return true


func remove_resident(human: Node2D) -> void:
	if not is_instance_valid(human):
		_prune()
		return
	_residents.erase(human)


func validate_definition() -> Array[String]:
	var errors: Array[String] = []
	if capacity < 1 or human_scene == null:
		errors.append("Nest needs a positive capacity and an ant scene")
	elif human_scene != null:
		var probe: Node = human_scene.instantiate()
		if not probe is AntAgent:
			errors.append("Nest resident scene must have an AntAgent root")
		probe.free()
	return errors

func _prune() -> void:
	var alive: Array[Node2D] = []
	for resident in _residents:
		if is_instance_valid(resident):
			alive.append(resident)
	_residents = alive

func _on_setup() -> bool:
	if option is SceneBuildOption and option.spawn_count > 0:
		capacity = option.spawn_count
	return true
