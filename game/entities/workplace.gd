class_name Workplace
extends Building

## Accounts for floating-point rounding when a full unit has just been produced.
const YIELD_ROUNDING_TOLERANCE := 0.000001

signal produced(type: ResourceType, amount: int)
signal supply_changed
signal improvement_changed

@export var recipe: WorkRecipe
var terrain_yield_multiplier := 1.0
var inventory: WorldInventory

@export_range(1, 1000) var work_slots: int = 1
## Raw resource output rate. The worker's work period determines the amount collected.
@export var output: ResourceType
@export_range(0.01, 1000.0, 0.01, "or_greater") var output_per_second := 1.0
## Finite sources count output units, not work cycles. Recipes use their input inventory.
@export var finite_supply := false:
	set(value):
		finite_supply = value
		if is_node_ready():
			refresh_appearance()
@export_range(0, 1000000) var remaining_supply := 100:
	set(value):
		remaining_supply = value
		if is_node_ready():
			refresh_appearance()
@export var improvement: WorkplaceUpgradeOption

@export_group("Expanded Deposit")
@export var expanded_deposit_type: ResourceType = preload("res://game/resources/resource_types/stone.tres")
@export_range(0, 1000000) var expanded_deposit_threshold := 200
@export var expanded_deposit_offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.RIGHT]
@export_group("")
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
	return true


func release_worker(human: Node2D) -> void:
	if _workers.has(human):
		_workers.erase(human)
		_working.erase(human)

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
	improvement_changed.emit()
	return true

func remove_improvement() -> void:
	if improvement == null:
		return
	work_slots -= _improvement_slots
	_improvement_slots = 0
	improvement = null
	refresh_appearance()
	improvement_changed.emit()

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
	_fit_appearance(sprite)

func footprint() -> Array[Vector2i]:
	if not finite_supply or remaining_supply <= expanded_deposit_threshold or output == null or expanded_deposit_type == null or output.id != expanded_deposit_type.id:
		return super.footprint()
	var cells: Array[Vector2i] = []
	for offset in expanded_deposit_offsets:
		cells.append(cell + offset)
	return cells

func display_title() -> String:
	return improvement.display_name if improvement != null else super.display_title()

func _on_setup() -> bool:
	if improvement != null:
		_improvement_slots = improvement.added_slots
		work_slots += _improvement_slots
	refresh_appearance()
	return true

func _ready() -> void:
	refresh_appearance()
	_remove_if_depleted()


## Completes one second of work for compatibility with one-shot workplace callers.
func complete_cycle(human: Node2D, keep_output: bool = false) -> bool:
	return complete_work_period(human, 1.0, keep_output)

func _complete_recipe_cycle(human: Node2D, keep_output: bool) -> bool:
	if not _workers.has(human):
		return false
	if keep_output and not _pending_output.is_empty():
		return true
	if not can_run_recipe():
		return false
	inventory.begin_update()
	if not inventory.try_spend_all(recipe.inputs):
		inventory.end_update()
		return false
	for entry in recipe.outputs: _produce(entry.type, entry.amount, keep_output)
	inventory.end_update()
	return true

func complete_work_period(human: Node2D, seconds: float, keep_output: bool = false) -> bool:
	if recipe != null:
		return _complete_recipe_cycle(human, keep_output)
	if not _workers.has(human) or output == null or not can_run_recipe(): return false
	if keep_output and not _pending_output.is_empty(): return true
	var amount := harvest_units(seconds)
	if amount > 0: _produce(output, amount, keep_output)
	return true

func harvest_units(seconds: float) -> int:
	return floori(resource_rate() * maxf(0.0, seconds) + YIELD_ROUNDING_TOLERANCE)

func resource_rate() -> float:
	return output_per_second * terrain_yield_multiplier if recipe == null and output != null else 0.0

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
	_remove_if_depleted()

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
	_remove_if_depleted()
	return cargo

func _remove_if_depleted() -> void:
	if finite_supply and remaining_supply <= 0 and _pending_output.is_empty() and is_inside_tree() and not is_queued_for_deletion():
		queue_free()

func validate_definition() -> Array[String]:
	var errors: Array[String] = []
	if recipe != null and not recipe.valid(): errors.append("Workplace has an invalid recipe")
	if work_slots < 1 or output == null and recipe == null or not is_finite(output_per_second) or output_per_second <= 0:
		errors.append("Workplace needs positive slots and a valid resource output rate")
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

func capture_production() -> Dictionary:
	return {"output": ResourceAmount.pack(_pending_output)}

func restore_production(state: Dictionary, output_items: Array[ResourceAmount]) -> void:
	_pending_output = output_items

func _apply_default_appearance(sprite: Sprite2D, art: ArtCatalog) -> void:
	if _source_texture != null:
		sprite.texture = _source_texture
		return
	if sprite.texture != null and (improvement == null or sprite.texture != improvement.icon):
		return
	var product: ResourceType = output
	if product == null and recipe != null and not recipe.outputs.is_empty():
		product = recipe.outputs[0].type
	match product.id if product != null else &"":
		&"food":
			sprite.texture = art.berries
		&"wood":
			sprite.texture = art.timber
		_:
			sprite.texture = art.stone

func _finalize_appearance(sprite: Sprite2D) -> void:
	refresh_appearance(sprite.texture)
