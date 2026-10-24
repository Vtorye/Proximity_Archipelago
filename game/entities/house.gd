class_name House
extends Building

const HUMAN_SCRIPT := preload("res://game/entities/human.gd")

@export var capacity: int = 5
@export var human_scene: PackedScene

var residents: Array[Node2D] = []


func _enter_tree() -> void:
	add_to_group("houses")


func has_space() -> bool:
	_prune()
	return residents.size() < capacity


func add_resident(human: Node2D) -> bool:
	if not is_instance_valid(human) or residents.has(human) or not has_space():
		return false
	residents.append(human)
	return true


func remove_resident(human: Node2D) -> void:
	if not is_instance_valid(human):
		_prune()
		return
	residents.erase(human)


func _on_setup() -> void:
	_populate()


func _on_demolish() -> void:
	remove_from_group("houses")
	var snapshot := residents.duplicate()
	for resident in snapshot:
		if is_instance_valid(resident):
			resident.die(HUMAN_SCRIPT.DeathCause.DEMOLISHED)
	residents.clear()


func _populate() -> void:
	if human_scene == null:
		push_error("House %s has no human_scene" % name)
		return
	var units := get_tree().get_first_node_in_group("units_root") as Node2D
	if units == null:
		push_error("House %s: no node in group units_root" % name)
		return
	var route_service := get_tree().get_first_node_in_group(&"route_service") as RouteService
	if route_service == null:
		push_error("House %s: no node in group route_service" % name)
		return
	_prune()
	for _i in range(capacity - residents.size()):
		var human = human_scene.instantiate()
		if not human is Node2D:
			push_error("House %s: human_scene root is not Node2D" % name)
			if human != null:
				human.free()
			return
		human.set("home", self)
		human.route_service = route_service
		units.add_child(human)
		human.global_position = global_position
		add_resident(human)


func _prune() -> void:
	residents = residents.filter(func(resident: Node2D) -> bool: return is_instance_valid(resident))
