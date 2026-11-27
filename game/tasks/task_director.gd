class_name TaskDirector
extends RefCounted
## Three royal orders without replacement; completion is tied to finished construction.
signal changed
enum Reward { ROAD, DISCOUNT, SPEED, SATIETY }
var world: World
var deck: TaskDeck
var pending_reward := false
var buffs: Array[int] = []
var level := 0
var closed := 0
var completed_count := 0
var skipped_count := 0
var slots: Array[TaskSpec] = []
var _pool: Array[TaskSpec] = []
var _rng := RandomNumberGenerator.new()
var _busy := false
var _speed := 1.0
var message := ""
var _upgrade_message := ""
var _construction_progress: Dictionary[StringName, int] = {}

func configure(colony: World, definitions: TaskDeck, random_seed: int = 0, opening_order: TaskSpec = null) -> void:
	world = colony
	deck = definitions
	_rng.seed = random_seed
	world.population.spawned.connect(func(ant: AntAgent): apply_ant_buffs(ant))
	world.registry.added.connect(func(building: Building): _skin(building))
	world.build_controller.can_place_order = can_place
	world.build_controller.order_placed.connect(changed.emit)
	world.build_controller.order_completed.connect(_on_order_completed)
	world.construction_service.order_cancelled.connect(changed.emit)
	_next_level(opening_order)

func stage() -> TaskStage:
	return deck.stages[mini(level - 1, deck.stages.size() - 1)]

func placed_order(task: TaskSpec) -> TaskBuildOrder:
	return world.construction_service.active_order_for(task)

func can_place(order: TaskBuildOrder, drafted := 0) -> bool:
	if order == null or order.task == null or not slots.has(order.task) or order.variant == null \
		or not order.task.variants.has(order.variant) or order.variant.building == null \
		or pending_reward or not world.match_controller.is_active():
		return false
	var placed := placed_order(order.task)
	if order.task.build_count == 1:
		return placed == null and drafted == 0
	if placed != null and placed.variant != order.variant:
		return false
	var pending := world.construction_service.active_order_count(order.task)
	return drafted + pending + _construction_progress.get(order.task.id, 0) < order.task.build_count

## Selecting an offer only prepares placement. A committed site locks its task.
func start_order(task_id: StringName, variant_id: StringName) -> TaskBuildOrder:
	var order := order_from_ids(task_id, variant_id)
	return order if can_place(order) else null

func order_from_ids(task_id: StringName, variant_id: StringName) -> TaskBuildOrder:
	for task in slots:
		if task != null and task.id == task_id:
			var variant := task.variant_by_id(variant_id)
			if variant != null and variant.building != null:
				return TaskBuildOrder.new(task, variant)
	return null

func _on_order_completed(order: TaskBuildOrder) -> void:
	var index := slots.find(order.task)
	if index < 0:
		return
	var done: int = _construction_progress.get(order.task.id, 0) + 1
	if done < order.task.build_count:
		_construction_progress[order.task.id] = done
		changed.emit()
		return
	_construction_progress.erase(order.task.id)
	var reward_seconds := order.time_reward()
	slots[index] = _pool.pop_back() if not _pool.is_empty() else null
	closed += 1
	_complete_task(order.task, reward_seconds, order.resources())
	message = "ui.task.time_reward:%d" % reward_seconds
	if closed == stage().tasks.size():
		if deck.choose_upgrades:
			pending_reward = true
		else:
			_apply_upgrade()
			advance()
	changed.emit()

func _complete_task(task: TaskSpec, reward_seconds: float, rewards: Array[ResourceAmount]) -> void:
	completed_count += 1
	world.inventory.begin_update()
	world.match_controller.add_time(reward_seconds)
	for entry in rewards: world.inventory.add(entry.type, entry.amount)
	for option in task.unlocks:
		world.build_controller.unlock_option(option)
	world.prices.record(GameEvents.Kind.TASK_COMPLETED, task.id)
	world.inventory.end_update()

func advance() -> void:
	if level == deck.stages.size() and not deck.loop_last_stage:
		world.match_controller.complete_objective()
	else: _next_level()

func reward_choices() -> Array[int]:
	return [Reward.SATIETY if buffs.has(Reward.ROAD) else Reward.ROAD, Reward.DISCOUNT, Reward.SPEED]

func reward_factor(kind: int) -> float:
	match kind:
		Reward.DISCOUNT: return deck.discount_reward_factor
		Reward.SPEED: return deck.speed_reward_factor
		Reward.SATIETY: return deck.satiety_reward_factor
	return 1.0

func choose_reward(index: int) -> bool:
	if not pending_reward or index < 0 or index >= 3 or not world.match_controller.is_active(): return false
	grant_buff(reward_choices()[index])
	pending_reward = false
	advance()
	changed.emit()
	return true

func apply_ant_buffs(ant: AntAgent) -> void:
	ant.speed *= _speed
	for buff in buffs:
		if buff == Reward.SATIETY:
			ant.needs.scale_capacity(reward_factor(buff))

func grant_buff(kind: int) -> void:
	buffs.append(kind)
	var factor := reward_factor(kind)
	match kind:
		Reward.ROAD: _unlock_road()
		Reward.DISCOUNT: world.prices.apply_multiplier(factor)
		Reward.SPEED: _increase_speed(factor)
		Reward.SATIETY:
			for ant in world.population.agents():
				ant.needs.scale_capacity(factor)

func _unlock_road() -> void:
	world.build_controller.unlock_option(deck.unlocked_road, deck.replaced_road)

func _increase_speed(factor: float) -> void:
	_speed *= factor
	for ant in world.population.agents(): ant.speed *= factor
	world.planner.queue_workplace_refresh()

func _next_level(opening_order: TaskSpec = null) -> void:
	if level > 0: message = _upgrade_message
	level += 1
	closed = 0
	_construction_progress.clear()
	_pool = stage().tasks.duplicate()
	for index in range(_pool.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var temporary: TaskSpec = _pool[index]
		_pool[index] = _pool[other]
		_pool[other] = temporary
	if opening_order != null and _pool.has(opening_order):
		_pool.erase(opening_order)
		_pool.append(opening_order)
	slots.clear()
	for index in range(3): slots.append(_pool.pop_back() if not _pool.is_empty() else null)
	for building in world.registry.all(): _skin(building)
	if level > 1: world.prices.record(GameEvents.Kind.LEVEL_ADVANCED, StringName(str(level)))
	changed.emit()

func _apply_upgrade() -> void:
	_upgrade_message = ["ui.task.trail_upgrade", "ui.task.cheap_building", "ui.task.faster_ants"][stage().upgrade]
	match stage().upgrade:
		0:
			_unlock_road()
		1: world.prices.apply_multiplier(stage().upgrade_factor)
		2: _increase_speed(stage().upgrade_factor)

func _skin(building: Building) -> void:
	if not building is House or deck.development_tints.is_empty(): return
	building.development_tint = deck.development_tints[mini(level - 1, deck.development_tints.size() - 1)]
	building.refresh_appearance()

func capture_state() -> Dictionary:
	return {
		"level": level, "closed": closed, "completed_count": completed_count,
		"skipped_count": skipped_count, "pending_reward": pending_reward,
		"buffs": buffs.duplicate(), "_speed": _speed,
		"message": message, "rng": _rng.state,
		"slots": slots.map(func(task: TaskSpec): return str(task.id) if task != null else ""),
		"pool": _pool.map(func(task: TaskSpec): return str(task.id)),
		"construction_progress": _construction_progress.duplicate(),
	}

func restore_state(state: Dictionary) -> void:
	var definitions: Dictionary[String, TaskSpec] = {}
	for task in deck.requests: definitions[str(task.id)] = task
	for stage_definition in deck.stages:
		for task in stage_definition.tasks:
			definitions[str(task.id)] = task
	_rng.state = state.rng
	level = state.level
	closed = state.closed
	_construction_progress.assign(state.get("construction_progress", {}))
	slots.clear()
	for id: String in state.slots:
		slots.append(definitions.get(deck.legacy_task_ids.get(id, id)))
	_pool.clear()
	for id: String in state.pool:
		var task: TaskSpec = definitions.get(deck.legacy_task_ids.get(id, id))
		if task != null:
			_pool.append(task)
	_restore_missing_offers()
	completed_count = state.completed_count
	skipped_count = state.skipped_count
	pending_reward = state.pending_reward
	buffs.assign(state.buffs)
	_speed = state._speed
	message = state.message
	changed.emit()

## If a task was removed without a replacement, keep the saved progress and
## offer unused tasks from the current stage until the player can finish it.
func _restore_missing_offers() -> void:
	var remaining := stage().tasks.size() - closed
	var available := _pool.size()
	for task in slots:
		if task != null:
			available += 1
	if available >= remaining:
		return
	for task in stage().tasks:
		if task == null or slots.has(task) or _pool.has(task):
			continue
		_pool.append(task)
		available += 1
		if available >= remaining:
			break
	for index in range(slots.size()):
		if slots[index] == null and not _pool.is_empty():
			slots[index] = _pool.pop_back()

func display_message() -> String:
	if message.begins_with("ui.task.time_reward:"):
		return tr("ui.task.time_reward") % int(message.get_slice(":", 1))
	return tr(message)
