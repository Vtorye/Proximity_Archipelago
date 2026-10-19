@abstract
class_name Workplace
extends Node2D

@export_range(1, 1000) var work_slots: int = 1
var workers: Array[Node2D] = []


func _enter_tree() -> void:
	add_to_group("workplaces")


func has_free_slot() -> bool:
	workers = workers.filter(func(worker: Node2D) -> bool: return is_instance_valid(worker))
	return workers.size() < work_slots


func reserve_worker(human: Node2D) -> bool:
	if workers.has(human) or not has_free_slot():
		return false
	workers.append(human)
	return true


func release_worker(human: Node2D) -> void:
	workers.erase(human)


@abstract func work_complete(human: Node2D) -> void
