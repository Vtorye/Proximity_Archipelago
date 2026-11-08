class_name Workplace
extends Building

signal produced(type: ResourceType, amount: int)
signal load_changed
signal supply_changed

@export var recipe: WorkRecipe
var terrain_yield_multiplier := 1.0
var _yield_remainder := 0.0
var inventory: WorldInventory
signal worker_arrived(worker: Node2D)
signal worker_left(worker: Node2D)

@export_range(1, 1000) var work_slots: int = 1
## Resource produced at the end of each work cycle. Leave empty for no output.
@export var output: ResourceType
@export var output_amount: int = 1
## Finite sources count output units, not work cycles. Recipes use their input inventory.
@export var finite_supply := false:
	set(value):
		finite_supply = value
		refresh_appearance()
@export_range(0, 1000000) var remaining_supply := 100:
	set(value):
		remaining_supply = value
		refresh_appearance()
@export var improvement: WorkplaceUpgradeOption
var _source_texture: Texture2D
var _improvement_slots := 0
var _pending_output: Array[ResourceAmount] = []
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
	if human is AntAgent and human.role != AntAgent.Role.WORKER:
		return false
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

func accepts_improvement(definition: WorkplaceUpgradeOption) -> bool:
	return matches_improvement(definition) and improvement == null and (not finite_supply or remaining_supply > 0)

func matches_improvement(definition: WorkplaceUpgradeOption) -> bool:
	return definition != null and definition.valid() and recipe == null and output != null and output.id == definition.source_type.id

func install_improvement(definition: WorkplaceUpgradeOption) -> bool:
	if not accepts_improvement(definition):
		return false
	improvement = definition
	_improvement_slots = definition.added_slots
	work_slots += _improvement_slots
	refresh_appearance()
	load_changed.emit()
	return true

func remove_improvement() -> void:
	if improvement == null:
		return
	work_slots -= _improvement_slots
	_improvement_slots = 0
	improvement = null
	refresh_appearance()
	load_changed.emit()

func refresh_appearance(source: Texture2D = null) -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	if source != null:
		_source_texture = source
	elif _source_texture == null:
		_source_texture = sprite.texture
	sprite.texture = improvement.icon if improvement != null else _source_texture
	sprite.visible = improvement != null or not finite_supply or remaining_supply > 0

func display_title() -> String:
	return improvement.display_name if improvement != null else super.display_title()

func _on_setup() -> bool:
	if improvement != null:
		_improvement_slots = improvement.added_slots
		work_slots += _improvement_slots
	refresh_appearance()
	return true


## Called by the worker when a work cycle finishes. Runs work_complete() and emits produced() if output is set.
func complete_cycle(human: Node2D, keep_output: bool = false) -> bool:
	if not _workers.has(human):
		return false
	if keep_output and not _pending_output.is_empty():
		return true
	if not can_run_recipe():
		return false
	if recipe != null:
		inventory.begin_update()
		if not inventory.try_spend_all(recipe.inputs):
			inventory.end_update()
			return false
		work_complete(human)
		for entry in recipe.outputs: _produce(entry.type, entry.amount, keep_output)
		inventory.end_update()
		return true
	work_complete(human)
	if output != null:
		var exact: float = output_amount * terrain_yield_multiplier + _yield_remainder
		# Carry fractional debt into the next cycle; the first harvest still yields a whole berry.
		var harvest: int = ceili(exact - 0.000001)
		_yield_remainder = exact - harvest
		if harvest > 0: _produce(output, harvest, keep_output)
	return true

func _produce(type: ResourceType, amount: int, keep_output: bool) -> void:
	if finite_supply:
		amount = mini(amount, remaining_supply)
		remaining_supply -= amount
		if amount == 0:
			return
	if keep_output and inventory != null and inventory.is_registered(type):
		var item := ResourceAmount.new()
		item.type = type
		item.amount = amount
		_pending_output.append(item)
	produced.emit(type, amount)
	if finite_supply:
		supply_changed.emit()

func pending_output_amount() -> int:
	return WorldInventory.cargo_size(_pending_output)

func take_output(limit: int) -> Array[ResourceAmount]:
	var cargo: Array[ResourceAmount] = []
	while limit > 0 and not _pending_output.is_empty():
		var pending: ResourceAmount = _pending_output[0]
		var amount: int = mini(pending.amount, limit)
		var item := ResourceAmount.new()
		item.type = pending.type
		item.amount = amount
		cargo.append(item)
		pending.amount -= amount
		limit -= amount
		if pending.amount == 0:
			_pending_output.pop_front()
	return cargo

func validate_definition() -> Array[String]:
	var errors: Array[String] = []
	if recipe != null and not recipe.valid(): errors.append("Workplace has an invalid recipe")
	if work_slots < 1 or output_amount < 1:
		errors.append("Workplace needs positive slots and output")
	if remaining_supply < 0 or finite_supply and recipe != null:
		errors.append("Finite supply needs a nonnegative amount and a raw resource source")
	if improvement != null and (not improvement.valid() or recipe != null or output == null or output.id != improvement.source_type.id):
		errors.append("Workplace improvement must match its raw resource source")
	return errors

func can_run_recipe() -> bool:
	if not _pending_output.is_empty(): return true
	if finite_supply and remaining_supply <= 0: return false
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
