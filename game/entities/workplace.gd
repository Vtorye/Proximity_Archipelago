@abstract
class_name Workplace
extends Building

signal produced(type: ResourceType, amount: int)

@export_range(1, 1000) var work_slots: int = 1
## Resource produced at the end of each work cycle. Leave empty for no output.
@export var output: ResourceType
@export var output_amount: int = 1
var workers: Array[Node2D] = []


func _enter_tree() -> void:
	add_to_group("workplaces")


func has_free_slot() -> bool:
	_prune_workers()
	return workers.size() < work_slots


## Drops freed units. Written as a loop: a typed lambda cannot receive a freed Object.
func _prune_workers() -> void:
	var alive: Array[Node2D] = []
	for worker in workers:
		if is_instance_valid(worker):
			alive.append(worker)
	workers = alive


func reserve_worker(human: Node2D) -> bool:
	if workers.has(human) or not has_free_slot():
		return false
	workers.append(human)
	return true


func release_worker(human: Node2D) -> void:
	workers.erase(human)


@abstract func work_complete(human: Node2D) -> void


## Called by the worker when a work cycle finishes. Runs work_complete() and emits produced() if output is set.
func complete_cycle(human: Node2D) -> void:
	work_complete(human)
	if output != null:
		produced.emit(output, output_amount)
