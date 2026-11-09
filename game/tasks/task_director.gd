class_name TaskDirector
extends RefCounted
## Three offers without replacement; payments, completion and rewards are one transaction.
signal changed
var world: World
var deck: TaskDeck
var pending_reward := false
var buffs: Array[int] = []
var difficulty_multiplier := 1.0
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

func configure(colony: World, definitions: TaskDeck, random_seed: int = 0) -> void:
	world = colony
	deck = definitions
	_rng.seed = random_seed
	world.population.spawned.connect(func(ant: AntAgent): apply_ant_buffs(ant))
	world.registry.added.connect(func(building: Building): _skin(building))
	_next_level()

func stage() -> TaskStage:
	return deck.stages[mini(level - 1, deck.stages.size() - 1)]

func price(index: int, cancel := false) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	if index < 0 or index >= slots.size() or slots[index] == null: return result
	if cancel and not slots[index].cancellation_costs.is_empty(): return slots[index].cancellation_costs.duplicate()
	var scale: float = difficulty_multiplier * pow(deck.repeat_cost_multiplier, maxi(0, level - deck.stages.size()))
	var totals: Dictionary[StringName, float] = {}
	var types: Dictionary[StringName, ResourceType] = {}
	for source in slots[index].costs:
		totals[source.type.id] = totals.get(source.type.id, 0.0) + source.amount
		types[source.type.id] = source.type
	for id in totals:
		if not is_finite(scale) or totals[id] * scale > 2147483647: return [null]
		var entry := ResourceAmount.new()
		entry.type = types[id]
		var quantity: int = ceili(totals[id] * scale - 0.000001)
		entry.amount = ceili(quantity * deck.cancellation_fraction - 0.000001) if cancel else quantity
		result.append(entry)
	return result

func can_pay(index: int, cancel := false) -> bool:
	return not _busy and not pending_reward and world.match_controller.is_active() and index >= 0 and index < slots.size() and slots[index] != null and world.inventory.can_afford_all(price(index, cancel))

func submit(index: int, cancel := false) -> bool:
	if not can_pay(index, cancel): return false
	_busy = true
	var task: TaskSpec = slots[index]
	var unlocked_names := PackedStringArray()
	world.inventory.begin_update()
	if not world.inventory.try_spend_all(price(index, cancel)):
		world.inventory.end_update()
		_busy = false
		return false
	if cancel: skipped_count += 1
	else: completed_count += 1
	if not cancel:
		world.match_controller.add_time(task.reward_seconds)
		for entry in task.rewards: world.inventory.add(entry.type, entry.amount)
		for option in task.unlocks:
			if not world.build_controller.options.has(option):
				world.build_controller.options.append(option)
				unlocked_names.append(TranslationServer.translate(option.display_name))
		if not unlocked_names.is_empty():
			world.prices.definitions = world.build_controller.options.duplicate()
			world.prices.changed.emit()
		world.events.publish(GameEvents.Kind.TASK_COMPLETED, task.id)
	closed += 1
	slots[index] = _pool.pop_back() if not _pool.is_empty() else null
	message = "Отказ: без времени и награды" if cancel else "+%d секунд" % task.reward_seconds
	if not unlocked_names.is_empty():
		message += " · " + ", ".join(unlocked_names)
	if closed == stage().tasks.size():
		if deck.choose_upgrades:
			pending_reward = true
		else:
			_apply_upgrade()
			advance()
	_busy = false
	world.inventory.end_update()
	changed.emit()
	return true

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
	_upgrade_message = ["Тропинка заменена на быструю", "Строительство дешевле", "Муравьи быстрее"][stage().upgrade]
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
