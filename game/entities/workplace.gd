class_name Workplace
extends Building

signal produced(type: ResourceType, amount: int)
signal load_changed

@export var recipe: WorkRecipe
var inventory: WorldInventory
signal worker_arrived(worker: Node2D)
signal worker_left(worker: Node2D)

@export_range(1, 1000) var work_slots: int = 1
## Resource produced at the end of each work cycle. Leave empty for no output.
@export var output: ResourceType
@export var output_amount: int = 1
var _workers: Array[Node2D] = []
var _working: Array[Node2D] = []
var workers: Array[Node2D]:
	get:
		_prune_workers()
		return _workers.duplicate()


func has_worker(worker: Node2D) -> bool:
	_prune_workers()
	return _workers.has(worker)

func worker_count() -> int:
	_prune_workers()
	return _workers.size()

func working_count() -> int:
	_prune_workers()
	return _working.size()

func incoming_count() -> int:
	return worker_count() - working_count()

func begin_work(worker: Node2D) -> bool:
	if not has_worker(worker):
		return false
	if not _working.has(worker):
		_working.append(worker)
		on_worker_arrived(worker)
		worker_arrived.emit(worker)
		load_changed.emit()
	return true

func has_free_slot() -> bool:
	_prune_workers()
	return _workers.size() < work_slots


## Drops freed units. Written as a loop: a typed lambda cannot receive a freed Object.
func _prune_workers() -> void:
	var alive: Array[Node2D] = []
	for worker in _workers:
		if is_instance_valid(worker):
			alive.append(worker)
	_workers = alive
	var active: Array[Node2D] = []
	for worker in _working:
		if is_instance_valid(worker) and _workers.has(worker): active.append(worker)
	_working = active


func reserve_worker(human: Node2D) -> bool:
	if not is_instance_valid(human) or _workers.has(human) or not has_free_slot():
		return false
	_workers.append(human)
	load_changed.emit()
	return true


func release_worker(human: Node2D) -> void:
	if _workers.has(human):
		on_worker_left(human)
		worker_left.emit(human)
		_workers.erase(human)
		_working.erase(human)
		load_changed.emit()


func work_complete(_human: Node2D) -> void:
	pass


## Called by the worker when a work cycle finishes. Runs work_complete() and emits produced() if output is set.
func complete_cycle(human: Node2D) -> bool:
	if not _workers.has(human) or not can_run_recipe():
		return false
	if recipe != null:
		inventory.begin_update()
		if not inventory.try_spend_all(recipe.inputs):
			inventory.end_update()
			return false
		work_complete(human)
		for entry in recipe.outputs: produced.emit(entry.type, entry.amount)
		inventory.end_update()
		return true
	work_complete(human)
	if output != null:
		produced.emit(output, output_amount)
	return true

func validate_definition() -> Array[String]:
	var errors: Array[String] = []
	if recipe != null and not recipe.valid(): errors.append("Workplace has an invalid recipe")
	if work_slots < 1 or output_amount < 1:
		errors.append("Workplace needs positive slots and output")
	return errors

func can_run_recipe() -> bool:
	if recipe == null: return true
	if inventory == null or not recipe.valid(): return false
	for entry in recipe.outputs:
		if not inventory.is_registered(entry.type): return false
	return inventory.can_afford_all(recipe.inputs)

## Extension hooks for specialized workplaces. The registry still owns membership.
func on_worker_arrived(_worker: Node2D) -> void:
	pass

func on_worker_left(_worker: Node2D) -> void:
	pass
