class_name TaskDirector
extends RefCounted
## Three royal orders without replacement; completion is tied to finished construction.
signal changed
var world: World
var deck: TaskDeck
var pending_reward := false
var buffs: Array[int] = []
var level := 0
var closed := 0
var completed_count := 0
var skipped_count := 0
var active_order_id: StringName = &""
var active_order_option: BuildOption
var active_order_diversion := false
var slots: Array[TaskSpec] = []
var _pool: Array[TaskSpec] = []
var _rng := RandomNumberGenerator.new()
var _busy := false
var _speed := 1.0
var message := ""
var _upgrade_message := ""

func configure(colony: World, definitions: TaskDeck, random_seed: int = 0) -> void:
	world = colony
	deck = definitions
	_rng.seed = random_seed
	world.population.spawned.connect(func(ant: AntAgent): apply_ant_buffs(ant))
	world.registry.added.connect(func(building: Building): _skin(building))
	world.build_controller.built.connect(_on_building_built)
	if world.build_controller.construction != null:
		world.build_controller.construction.cancelled.connect(cancel_unplaced_order)
	_next_level()

func stage() -> TaskStage:
	return deck.stages[mini(level - 1, deck.stages.size() - 1)]

func submit(index: int, cancel := false) -> bool:
	return false

func start_order(index: int, diversion: bool = false) -> BuildOption:
	if index < 0 or index >= slots.size() or slots[index] == null or pending_reward or not world.match_controller.is_active(): return null
	if active_order_id != &"": return null
	var task: TaskSpec = slots[index]
	var option: BuildOption = task.diversion if diversion else task.building
	if option == null: return null
	world.build_controller.order_option = option
	active_order_id = task.id
	active_order_option = option
	active_order_diversion = diversion
	changed.emit()
	return option

func cancel_unplaced_order(option: BuildOption) -> void:
	if option != active_order_option: return
	var construction := world.build_controller.construction
	if construction != null and construction.sites.any(func(site: ConstructionSite) -> bool: return site.option == option):
		return
	_clear_order()
	changed.emit()

func _clear_order() -> void:
	active_order_id = &""
	active_order_option = null
	active_order_diversion = false
	world.build_controller.order_option = null

func _on_building_built(option: BuildOption, _cell: Vector2i) -> void:
	if active_order_id == &"" or option != active_order_option: return
	for index in range(slots.size()):
		if slots[index] != null and slots[index].id == active_order_id:
			var task: TaskSpec = slots[index]
			var reward_seconds := task.time_reward_for(active_order_diversion)
			var variant_rewards := task.resources_for(active_order_diversion)
			_clear_order()
			_complete_task(task, reward_seconds, variant_rewards)
			closed += 1
			slots[index] = _pool.pop_back() if not _pool.is_empty() else null
			message = "ui.task.time_reward:%d" % reward_seconds
			if closed == stage().tasks.size():
				if deck.choose_upgrades: pending_reward = true
				else:
					_apply_upgrade()
					advance()
			changed.emit()
			return

func _complete_task(task: TaskSpec, reward_seconds: float, rewards: Array[ResourceAmount]) -> void:
	completed_count += 1
	world.inventory.begin_update()
	world.match_controller.add_time(reward_seconds)
	for entry in rewards: world.inventory.add(entry.type, entry.amount)
	var unlocked_names := PackedStringArray()
	for option in task.unlocks:
		if not world.build_controller.options.has(option):
			world.build_controller.options.append(option)
			unlocked_names.append(TranslationServer.translate(option.display_name))
	if not unlocked_names.is_empty():
		world.prices.definitions = world.build_controller.options.duplicate()
		world.prices.changed.emit()
	world.events.publish(GameEvents.Kind.TASK_COMPLETED, task.id)
	world.inventory.end_update()

func advance() -> void:
	if level == deck.stages.size() and not deck.loop_last_stage:
		world.match_controller.complete_objective()
	else: _next_level()

func reward_choices() -> Array[int]:
	return [3 if buffs.has(0) else 0, 1, 2]

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
		if buff == 3:
			ant.needs.capacity *= 1.2
			ant.needs.satiety *= 1.2

func grant_buff(kind: int) -> void:
	buffs.append(kind)
	match kind:
		0: _unlock_road()
		1:
			world.prices.global_multiplier *= 0.9
			world.prices.changed.emit()
		2:
			_speed *= 1.15
			for ant in world.population.agents(): ant.speed *= 1.15
			world.planner.opportunities_changed.emit()
		3:
			for ant in world.population.agents():
				ant.needs.capacity *= 1.2
				ant.needs.satiety *= 1.2

func _unlock_road() -> void:
	if deck.unlocked_road == null or world.build_controller.options.has(deck.unlocked_road): return
	var position: int = world.build_controller.options.find_custom(func(option: BuildOption) -> bool:
		return deck.replaced_road != null and option.id == deck.replaced_road.id)
	if position >= 0: world.build_controller.options[position] = deck.unlocked_road
	else: world.build_controller.options.append(deck.unlocked_road)
	world.prices.definitions = world.build_controller.options.duplicate()
	world.prices.changed.emit()

func _next_level() -> void:
	if level > 0: message = _upgrade_message
	level += 1
	closed = 0
	_pool = stage().tasks.duplicate()
	for index in range(_pool.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var temporary: TaskSpec = _pool[index]
		_pool[index] = _pool[other]
		_pool[other] = temporary
	slots.clear()
	for index in range(3): slots.append(_pool.pop_back() if not _pool.is_empty() else null)
	for building in world.registry.all(): _skin(building)
	if level > 1: world.events.publish(GameEvents.Kind.LEVEL_ADVANCED, StringName(str(level)))
	changed.emit()

func _apply_upgrade() -> void:
	_upgrade_message = ["ui.task.trail_upgrade", "ui.task.cheap_building", "ui.task.faster_ants"][stage().upgrade]
	match stage().upgrade:
		0:
			_unlock_road()
		1:
			world.prices.global_multiplier *= stage().upgrade_factor
			world.prices.changed.emit()
		2:
			_speed *= stage().upgrade_factor
			for ant in world.population.agents(): ant.speed *= stage().upgrade_factor
			world.planner.opportunities_changed.emit()

func _skin(building: Building) -> void:
	if not building is House: return
	building.development_tint = [Color.WHITE, Color("efd38e"), Color("a8d4e9"), Color("d2b3ed")][mini(level - 1, 3)]
	building.refresh_appearance()

func capture_state() -> Dictionary:
	return {
		"level": level, "closed": closed, "completed_count": completed_count,
		"skipped_count": skipped_count, "pending_reward": pending_reward,
		"buffs": buffs.duplicate(), "_speed": _speed,
		"message": message, "rng": _rng.state,
		"active_order_id": str(active_order_id),
		"active_order_diversion": active_order_diversion,
		"slots": slots.map(func(task: TaskSpec): return str(task.id) if task != null else ""),
		"pool": _pool.map(func(task: TaskSpec): return str(task.id)),
	}

func restore_state(state: Dictionary) -> void:
	var definitions: Dictionary[String, TaskSpec] = {}
	for task in deck.requests: definitions[str(task.id)] = task
	for stage_definition in deck.stages:
		for task in stage_definition.tasks:
			definitions[str(task.id)] = task
	slots.clear()
	for id in state.slots:
		slots.append(definitions.get(id))
	_pool.clear()
	for id in state.pool:
		_pool.append(definitions[id])
	_rng.state = state.rng
	level = state.level
	closed = state.closed
	completed_count = state.completed_count
	skipped_count = state.skipped_count
	pending_reward = state.pending_reward
	buffs.assign(state.buffs)
	_speed = state._speed
	message = state.message
	active_order_id = StringName(state.get("active_order_id", ""))
	active_order_diversion = state.get("active_order_diversion", false)
	active_order_option = null
	for task in slots:
		if task != null and task.id == active_order_id:
			active_order_option = task.diversion if active_order_diversion else task.building
			break
	if active_order_option == null:
		active_order_id = &""
	world.build_controller.order_option = active_order_option
	if active_order_option != null:
		cancel_unplaced_order(active_order_option)
	changed.emit()

func display_message() -> String:
	if message.begins_with("ui.task.time_reward:"):
		return tr("ui.task.time_reward") % int(message.get_slice(":", 1))
	return tr(message)
