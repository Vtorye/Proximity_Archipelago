class_name ZeroChapter
extends FirstChapter
## The new opening uses the same match and construction interfaces as saved first chapters.

signal camera_follow_requested(actor: Node2D)

## Snapshots preserve their authored map, including the original, intramural quarry.
const ORIGINAL_QUARRY_CELL := Vector2i(31, 19)
const ORIGINAL_QUARRY_ROADS: Array[Vector2i] = [
	Vector2i(32, 21), Vector2i(32, 20), Vector2i(31, 20), ORIGINAL_QUARRY_CELL]

enum Phase { INTRO, ORDERS = 2, WALL, STATUES, REMOVE_WALL, REMOVE_STATUE, REMOVE_SOURCE,
	QUARRY, BRIEFING, PREPARATION, MILITARY, BREACH, DEMAND, EVACUATION, ESCORT, FAREWELL, COMPLETE }

var phase := Phase.INTRO
var skip_lessons := false
var _zero: ZeroChapterRules
var _stone: ResourceType
var _quarry_cell: Vector2i
var _quarry_roads: Array[Vector2i] = []
var _saw_priority := false
var _quarry_mined := 0
var _wall_ordered := false
var _breach_running := false
var _runner: Node2D
var _spider: SpiderAgent

func configure(colony: World, dialogue: StoryOverlay) -> void:
	super.configure(colony, dialogue)
	_zero = colony.chapter_rules as ZeroChapterRules
	_stone = colony.inventory.type_by_id(&"stone")
	_quarry_cell = _zero.finite_stone_cell
	_quarry_roads = _zero.quarry_roads
	var quarry := colony.registry.at(_quarry_cell) as Workplace
	if quarry == null:
		var original := colony.registry.at(ORIGINAL_QUARRY_CELL) as Workplace
		if original != null and original.output == _stone:
			_quarry_cell = ORIGINAL_QUARRY_CELL
			_quarry_roads = ORIGINAL_QUARRY_ROADS
			quarry = original
	if quarry != null:
		quarry.produced.connect(_on_quarry_produced)
	var old_source := colony.registry.at(_zero.stone_cell) as Workplace
	if old_source != null:
		old_source.improvement_changed.connect(_on_old_source_improvement_changed.bind(old_source))
	colony.logistics.stock_transferred.connect(_on_stock_transferred)
	var depot := _demonstration_depot()
	if depot != null:
		depot.stock_order_changed.connect(_resume_hint)
	colony.population.allow_warriors = false
	story.set_lesson_skip(true)
	story.lesson_skip_requested.connect(_skip_lessons)

func start(saved: Dictionary = {}) -> void:
	_starting = false
	set_process(true)
	if not saved.is_empty():
		restore_state(saved)
		_resume()
	elif skip_lessons:
		_skip_lessons()
	else:
		world.inventory.quantities_known = false
		story.play("intro")

func save_layout_id() -> String:
	return LevelLayout.ZERO_ISLAND_ID

func countdown_visible() -> bool:
	return phase == Phase.PREPARATION

func shows_control(control: StringName) -> bool:
	if phase == Phase.INTRO:
		return super.shows_control(control)
	match control:
		&"build": return allows_section(control)
		&"tasks": return phase == Phase.STATUES
		&"routes": return phase in [Phase.ORDERS, Phase.QUARRY, Phase.PREPARATION]
	return true

func allows_section(section: StringName) -> bool:
	if phase == Phase.INTRO:
		return super.allows_section(section)
	if section == &"tasks":
		return phase == Phase.STATUES
	return section in [&"talk", &"colony"] or section == &"build" and phase in [
		Phase.ORDERS, Phase.WALL, Phase.REMOVE_WALL, Phase.REMOVE_STATUE,
		Phase.REMOVE_SOURCE, Phase.QUARRY, Phase.PREPARATION]

func allows_order(task_id: StringName, variant_id: StringName) -> bool:
	if phase == Phase.INTRO:
		return super.allows_order(task_id, variant_id)
	return phase == Phase.STATUES and task_id == _zero.statue_order.id

func allows_tool(option: BuildOption, order: TaskBuildOrder = null) -> bool:
	if _scripted:
		return true
	if phase == Phase.INTRO:
		if stage == Stage.FREE_BUILD:
			if story.is_modal or order != null:
				return false
			if option == null:
				return _can_remove_lesson_upgrade(_zero.timber_cell) or _can_remove_lesson_upgrade(_zero.stone_cell) or _can_remove_lesson_upgrade(_quarry_cell)
			return option == _zero.road or option == _zero.wishes[1] or option == _zero.wishes[2]
		return super.allows_tool(option, order)
	if story.is_modal:
		return false
	if order != null:
		return option == _zero.statue and allows_order(order.task.id, order.variant.id)
	match phase:
		Phase.QUARRY: return option == _zero.road or option is NestBuildOption or option == _zero.wishes[2]
		Phase.ORDERS: return option is NestBuildOption
		Phase.WALL: return option == _zero.wall
		Phase.REMOVE_WALL, Phase.REMOVE_STATUE, Phase.REMOVE_SOURCE: return option == null
		Phase.PREPARATION: return option == null or option is NestBuildOption or option in [
			_zero.road, _zero.ship, _zero.wishes[1], _zero.wishes[2], _zero.ground]
	return false

func allows_placement(option: BuildOption, cell: Vector2i, order: TaskBuildOrder = null) -> bool:
	if _scripted:
		return true
	if phase == Phase.INTRO:
		if stage == Stage.FREE_BUILD and option == null:
			return not story.is_modal and _can_remove_lesson_upgrade(cell)
		return super.allows_placement(option, cell, order)
	if not allows_tool(option, order):
		return false
	match phase:
		Phase.QUARRY: return not option is WorkplaceUpgradeOption or cell == _quarry_cell
		Phase.ORDERS: return option is NestBuildOption
		Phase.WALL: return cell == _zero.wall_cell
		Phase.REMOVE_WALL: return _zero.demolition_wall_cells.has(cell)
		Phase.STATUES: return _zero.statue_cells.has(cell)
		Phase.REMOVE_STATUE: return _zero.statue_cells.has(cell)
		Phase.REMOVE_SOURCE: return cell == _zero.stone_cell
		Phase.PREPARATION:
			if option == _zero.ship:
				return cell == _zero.ship_cell
			var building := world.registry.at(cell)
			if option == null and building != null and not building is ConstructionSite:
				if building is DefenseBuilding and not _zero.protected_walls.grow(-1).has_point(cell):
					return false
				return not building is House and building != ship() and cell != _quarry_cell
			return true
	return false

func _can_remove_lesson_upgrade(cell: Vector2i) -> bool:
	if cell != _zero.timber_cell and cell != _zero.stone_cell and cell != _quarry_cell:
		return false
	var target := world.build_controller.demolition_target(cell)
	return (target is ConstructionSite and target.option is WorkplaceUpgradeOption) or (
		target is Workplace and target.improvement != null)

func _lesson_has_sawmill() -> bool:
	var source := world.registry.at(_zero.timber_cell) as Workplace
	return source != null and source.improvement == _zero.wishes[1]

func _lesson_has_quarry() -> bool:
	for cell in [_zero.stone_cell, _quarry_cell]:
		var source := world.registry.at(cell) as Workplace
		if source != null and source.improvement == _zero.wishes[2]:
			return true
	return false

func preferred_option() -> StringName:
	if phase == Phase.INTRO:
		if stage == Stage.FREE_BUILD:
			return _zero.wishes[2 if _lesson_has_sawmill() else 1].id
		return super.preferred_option()
	match phase:
		Phase.QUARRY: return _zero.road.id
		Phase.WALL: return _zero.wall.id
		Phase.PREPARATION: return _zero.ship.id if ship() == null else _zero.road.id
	return &""

func highlighted_control() -> StringName:
	if phase == Phase.INTRO:
		return super.highlighted_control()
	if phase == Phase.STATUES:
		return &"tasks"
	return &"routes" if phase == Phase.QUARRY and not _saw_priority else &""

func guide_cell() -> Vector2i:
	match phase:
		Phase.QUARRY: return _quarry_cell
		Phase.ORDERS: return _zero.delivery_cell
		Phase.WALL: return _zero.wall_cell
		Phase.REMOVE_WALL:
			for cell in _zero.demolition_wall_cells:
				if world.registry.at(cell) != null:
					return cell
		Phase.STATUES, Phase.REMOVE_STATUE:
			for cell in _zero.statue_cells:
				# Highlight the next placement or the statue opening the central path.
				if phase == Phase.STATUES and world.registry.at(cell) == null or phase == Phase.REMOVE_STATUE:
					return cell
		Phase.REMOVE_SOURCE: return _zero.stone_cell
		Phase.PREPARATION, Phase.EVACUATION:
			if ship() == null or phase == Phase.EVACUATION:
				return _zero.ship_cell
	return super.guide_cell()

func guide_cells() -> Array[Vector2i]:
	match phase:
		Phase.INTRO:
			if stage == Stage.FREE_BUILD:
				var targets: Array[Vector2i] = []
				if not _lesson_has_sawmill():
					targets.append(_zero.timber_cell)
				if not _lesson_has_quarry():
					targets.append(_zero.stone_cell)
				return targets
		Phase.STATUES: return _zero.statue_cells.filter(func(cell: Vector2i): return not _complete_building(cell, _zero.statue))
		Phase.REMOVE_WALL: return _zero.demolition_wall_cells.filter(func(cell: Vector2i): return world.registry.at(cell) != null)
	return super.guide_cells()

func navigation_changed(mode: int) -> void:
	if mode == 2:
		_saw_priority = true
		_resume_hint()

func status_text() -> String:
	if phase == Phase.INTRO:
		if stage == Stage.FREE_BUILD:
			if _lesson_has_sawmill():
				return tr("ui.zero.quarry_upgrade_goal")
			if _lesson_has_quarry():
				return tr("ui.zero.sawmill_upgrade_goal")
			return tr("ui.zero.upgrades_goal")
		return super.status_text()
	match phase:
		Phase.ORDERS:
			var depot := _demonstration_depot()
			if depot == null:
				return ""
			var order := depot.order_of(str(_stone.id))
			if not depot.orders.has(str(_stone.id)) or int(order.max) <= _zero.depot_minimum:
				return tr("ui.zero.set_max") % _zero.depot_maximum
			if int(order.min) == 0 or int(order.min) == int(order.max):
				return tr("ui.zero.set_min") % _zero.depot_minimum
			return tr("ui.zero.wait_transfer")
		Phase.WALL: return tr("ui.zero.wall_goal")
		Phase.STATUES:
			var finished := 0
			for cell in _zero.statue_cells:
				if _complete_building(cell, _zero.statue):
					finished += 1
			return tr("ui.zero.statues_goal") % [finished, _zero.statue_cells.size()]
		Phase.REMOVE_WALL: return tr("ui.zero.remove_wall_goal")
		Phase.REMOVE_STATUE: return tr("ui.zero.remove_statue_goal")
		Phase.REMOVE_SOURCE: return tr("ui.zero.remove_source_goal")
		Phase.QUARRY:
			return tr("ui.zero.quarry_goal") % [_quarry_mined, _zero.quarry_target]
		Phase.PREPARATION:
			var boat := ship()
			var lines := PackedStringArray([
				tr("ui.zero.ship_done" if boat != null else "ui.zero.ship_goal"),
				tr("ui.zero.road_done" if _queen_route_ready() else "ui.zero.escape_road_goal")])
			var cargo := PackedStringArray()
			for item in _zero.minimum_cargo:
				cargo.append("%s %d/%d" % [tr(item.type.display_name),
					boat.manifest.get(str(item.type.id), 0) if boat != null else 0, item.amount])
			lines.append(" · ".join(cargo))
			var depot := _quarry_depot()
			if boat != null and is_instance_valid(depot) and world.logistics.order_surplus(depot, _stone) == 0:
				lines.append(tr("ui.zero.reserve_hint"))
			return "\n".join(lines)
		Phase.EVACUATION: return tr("ui.zero.board_goal")
		Phase.ESCORT: return tr("ui.chapter.escort_hint")
	return ""

func _complete_building(cell: Vector2i, option: BuildOption) -> bool:
	var building := world.registry.at(cell)
	return building != null and not building is ConstructionSite and building.option == option

func _queen_route_ready() -> bool:
	return not world.queen.route_to(landing_cell()).is_empty()

func topic_available(character: StoryCharacter) -> bool:
	if character.id == &"Protagonist":
		return false
	if phase == Phase.INTRO:
		return super.topic_available(character)
	return phase in [Phase.ORDERS, Phase.QUARRY, Phase.PREPARATION] and character.id in [&"Courier", &"Worker"] or (
		phase in [Phase.QUARRY, Phase.PREPARATION] and character.id == &"Planner")

func talk(character: StoryCharacter) -> void:
	if phase == Phase.INTRO:
		super.talk(character)
		return
	if topic_available(character) and not story.is_modal:
		story.play(str(character.topic))

func reprimand(_reason: StringName = &"action") -> void:
	if not story.is_modal:
		story.flash_warning("ui.zero.check_goal")

func _on_action(action: StringName) -> void:
	match action:
		&"road":
			super._on_action(action)
			if _is_road(_zero.road_cell):
				story.play.call_deferred("after_road")
		&"orders": _enter(Phase.ORDERS)
		&"wall":
			_wall_ordered = true
			_enter(Phase.WALL)
		&"statues":
			_enter(Phase.STATUES)
		&"remove_wall": _enter(Phase.REMOVE_WALL)
		&"remove_statue": _enter(Phase.REMOVE_STATUE)
		&"remove_source": _enter(Phase.REMOVE_SOURCE)
		&"quarry": _enter(Phase.QUARRY)
		&"preparation": _begin_preparation()
		&"free":
			super._on_action(action)
			focus_requested.emit(_zero.timber_cell)
		&"breach": _enter(Phase.BREACH)
		&"evacuation":
			if is_instance_valid(_spider):
				_spider.set_physics_process(true)
			_enter(Phase.EVACUATION)
		&"depart":
			_enter(Phase.COMPLETE)
			_depart()
		_: super._on_action(action)

func _enter(next: Phase, focus := true) -> void:
	phase = next
	world.build_controller.demolition_limit = 1 if phase == Phase.REMOVE_STATUE else 0
	# Saved phase IDs predate the current lesson order. The courier now follows the planner.
	world.inventory.quantities_known = phase not in [Phase.INTRO, Phase.WALL, Phase.STATUES]
	story.set_lesson_skip(phase < Phase.PREPARATION)
	presentation_changed.emit()
	_resume_hint()
	var target := guide_cell()
	if focus and world.map.get_used_rect().has_point(target):
		focus_requested.emit(target)

func _complete_lesson(next: Phase, scene: String) -> void:
	_enter(next, false)
	story.play(scene)

func _process(_delta: float) -> void:
	if _starting or story.is_modal or get_tree().paused or world.match_controller.is_finished():
		return
	# Observe committed world state. A plan can contain several builds/removals in one transaction.
	match phase:
		Phase.INTRO:
			if stage == Stage.FREE_BUILD and _lesson_has_sawmill() and _lesson_has_quarry():
				_complete_lesson(Phase.STATUES, "statues")
		Phase.ORDERS:
			if _transport_delivered > 0: _complete_lesson(Phase.BRIEFING, "briefing")
		Phase.WALL:
			if _complete_building(_zero.wall_cell, _zero.wall): _complete_lesson(Phase.INTRO, "early_requests")
		Phase.STATUES:
			if _zero.statue_cells.all(func(cell: Vector2i): return _complete_building(cell, _zero.statue)):
				_complete_lesson(Phase.REMOVE_WALL, "planner")
		Phase.REMOVE_WALL:
			if _zero.demolition_wall_cells.all(func(cell: Vector2i): return world.registry.at(cell) == null):
				_complete_lesson(Phase.REMOVE_STATUE, "remove_statue")
		Phase.REMOVE_STATUE:
			if _zero.statue_cells.any(func(cell: Vector2i): return world.registry.at(cell) == null):
				_complete_lesson(Phase.REMOVE_SOURCE, "caught")
		Phase.REMOVE_SOURCE:
			if world.registry.at(_zero.stone_cell) == null:
				_complete_lesson(Phase.QUARRY, "mentor")
		Phase.QUARRY:
			if _quarry_mined >= _zero.quarry_target: _complete_lesson(Phase.ORDERS, "orders")
		Phase.PREPARATION:
			if ship() != null and ship().supplied() and _queen_route_ready():
				world.match_controller.countdown_suspended = true
				_enter(Phase.MILITARY, false)
				_run_military()
		Phase.BREACH:
			if not _breach_running: _run_breach()

func _on_quarry_produced(type: ResourceType, amount: int) -> void:
	if phase == Phase.QUARRY and type == _stone:
		_quarry_mined = mini(_quarry_mined + amount, _zero.quarry_target)
		_resume_hint()

func _on_stock_transferred(source: House, target: Building, type: ResourceType, amount: int) -> void:
	if phase == Phase.ORDERS and source != target and target == _demonstration_depot() and type == _stone:
		var order := (target as House).order_of(str(type.id))
		if int(order.min) > 0 and int(order.max) > int(order.min):
			_transport_delivered += amount

func _on_built(option: BuildOption, _cell: Vector2i) -> void:
	if phase == Phase.INTRO:
		if stage == Stage.FREE_BUILD:
			_resume_hint()
		else:
			super._on_built(option, _cell)
		return
	if option == _zero.ship:
		_configure_ship()
	_resume_hint()

func _on_shipment_delivered(_target: Building, _type: ResourceType, _amount: int) -> void:
	if phase == Phase.PREPARATION:
		_resume_hint()

func _on_construction_changed() -> void:
	_resume_hint()

func _on_old_source_improvement_changed(source: Workplace) -> void:
	if phase == Phase.REMOVE_SOURCE and source.improvement == null:
		# Wait until the player-confirmed demolition finishes its transaction.
		_demolish_old_source.call_deferred()

func _demolish_old_source() -> void:
	if world.registry.at(_zero.stone_cell) is Workplace:
		world.build_controller.demolish_at(_zero.stone_cell)
		if world.registry.at(_zero.stone_cell) is Workplace:
			world.build_controller.demolish_at(_zero.stone_cell)

func _configure_ship() -> void:
	super._configure_ship()
	var boat := ship()
	if boat != null:
		boat.accepting_cargo = phase == Phase.PREPARATION

func _begin_preparation() -> void:
	_balance_preparation_stock()
	var depot := _quarry_depot()
	if depot != null:
		depot.set_order(str(_stone.id), "max", _zero.quarry_depot_reserve)
		depot.set_order(str(_stone.id), "min", _zero.quarry_depot_reserve)
	for option in [_zero.ship, _zero.wishes[1], _zero.wishes[2]]:
		world.build_controller.unlock_option(option)
	world.match_controller.reset_countdown(_zero.preparation_seconds)
	world.match_controller.countdown_suspended = false
	_enter(Phase.PREPARATION)
	_configure_ship()
	checkpoint_requested.emit(CHECKPOINT)

func _quarry_depot() -> House:
	return world.registry.at(_zero.quarry_depot_cell) as House

func _balance_preparation_stock() -> void:
	for budget in _zero.preparation_stock:
		var difference := budget.amount - world.inventory.available(budget.type)
		if difference >= 0:
			world.inventory.add(budget.type, difference)
		else:
			var excess := ResourceAmount.new()
			excess.type = budget.type
			excess.amount = -difference
			world.inventory.try_spend_all([excess])

func _skip_lessons() -> void:
	if phase >= Phase.PREPARATION:
		return
	story.finish()
	_scripted = true
	world.build_controller.demolition_limit = 0
	var pending: Array[BuildCommand] = []
	for site in world.construction_service.sites:
		pending.append(BuildCommand.remove(site))
	world.build_controller.try_build_plan(pending)
	_demolish_old_source()
	for cell in _zero.demolition_wall_cells:
		if _complete_building(cell, _zero.wall):
			world.build_controller.demolish_at(cell)
	var roads: Array[Vector2i] = [_zero.road_cell]
	roads.append_array(_quarry_roads)
	for cell in roads:
		if not _is_road(cell) and world.route_service.walkable(cell):
			world.build_controller.apply_surface(_zero.road, cell)
	world.route_service.rebuild(world.registry.blocked_cells())
	_scripted = false
	_begin_preparation()

func _run_military() -> void:
	var military := _zero.military_scene.instantiate() as Node2D
	world.add_child(military)
	_runner = military
	_runner.global_position = world.route_service.cell_to_world(_zero.military_entry)
	camera_follow_requested.emit(_runner)
	var route := world.route_service.request_route(_zero.military_entry, _zero.military_destination)
	var movement := _runner.create_tween()
	if route.is_valid():
		for index in range(1, route.cells.size()):
			movement.tween_property(_runner, "global_position", world.route_service.cell_to_world(route.cells[index]),
				world.route_service.cell_size() / _zero.military_speed)
	else:
		movement.tween_property(_runner, "global_position",
			world.route_service.cell_to_world(_zero.military_destination),
			_runner.global_position.distance_to(world.route_service.cell_to_world(_zero.military_destination)) / _zero.military_speed)
	await movement.finished
	camera_follow_requested.emit(null)
	story.play("military")

func _run_breach() -> void:
	_breach_running = true
	var wall := world.registry.at(_zero.breach_cell)
	_spider = world.combat.spiders.front() if not world.combat.spiders.is_empty() else world.combat.spawn_spider(_zero.spider_entry)
	if is_instance_valid(_spider) and is_instance_valid(wall):
		_spider.set_physics_process(false)
		var approach := world.combat.approach(wall, _zero.spider_entry)
		if approach.is_valid():
			var stride := _spider.create_tween()
			for index in range(1, approach.cells.size()):
				stride.tween_property(_spider, "global_position", world.route_service.cell_to_world(approach.cells[index]),
					world.route_service.cell_size() / _zero.approach_speed)
			focus_requested.emit(_zero.breach_cell)
			if approach.cells.size() > 1:
				await stride.finished
		await get_tree().create_timer(_zero.breach_delay, false).timeout
		if is_instance_valid(wall):
			world.combat.damage(wall, world.combat.maximum_health(wall))
	_enter(Phase.DEMAND, false)
	story.play("spider")

func can_evacuate() -> bool:
	var boat := ship()
	return phase == Phase.EVACUATION and boat != null and boat.supplied() and _queen_route_ready()

func evacuate() -> void:
	if can_evacuate() and world.queen.depart(landing_cell()):
		world.queen.show()
		_enter(Phase.ESCORT, false)
		camera_follow_requested.emit(world.queen)

func _on_queen_arrived() -> void:
	camera_follow_requested.emit(null)
	_complete_lesson(Phase.FAREWELL, "farewell")

func travellers() -> Array[String]:
	return ["Queen", "Protagonist", "Courier", "Worker", "Military"]

func capture_state() -> Dictionary:
	var state := super.capture_state()
	state.merge({"phase": phase, "seen_priority": _saw_priority,
		"quarry_mined": _quarry_mined, "wall_ordered": _wall_ordered})
	state["version"] = 3
	return state

func restore_state(saved: Dictionary) -> void:
	super.restore_state(saved)
	phase = clampi(int(saved.get("phase", Phase.INTRO)), Phase.INTRO, Phase.COMPLETE) as Phase
	_saw_priority = saved.get("seen_priority", false)
	_quarry_mined = clampi(int(saved.get("quarry_mined", 0)), 0, _zero.quarry_target)
	_wall_ordered = saved.get("wall_ordered", false)
	if int(saved.get("version", 2)) == 2 and (
			int(phase) == 1 or phase == Phase.ORDERS and world.registry.at(_zero.stone_cell) != null):
		phase = Phase.INTRO
		stage = Stage.WORKER_ADVICE if not _first_choice.is_empty() else Stage.INTRO

func _resume() -> void:
	world.match_controller.countdown_suspended = phase != Phase.PREPARATION
	_spider = world.combat.spiders.front() if not world.combat.spiders.is_empty() else null
	_enter(phase, false)
	_configure_ship()
	match phase:
		Phase.INTRO:
			if stage == Stage.FREE_BUILD and _lesson_has_sawmill() and _lesson_has_quarry():
				_complete_lesson(Phase.STATUES, "statues")
			elif stage == Stage.ROAD and _is_road(_zero.road_cell):
				story.play("early_requests" if _wall_ordered else "after_road")
			else:
				super._resume()
		Phase.BRIEFING: story.play("briefing")
		Phase.MILITARY: _run_military()
		Phase.BREACH, Phase.DEMAND:
			if is_instance_valid(_spider): _spider.set_physics_process(false)
			if phase == Phase.DEMAND: story.play("spider")
		Phase.ESCORT:
			world.queen.show()
			world.queen.depart(landing_cell())
			camera_follow_requested.emit(world.queen)
		Phase.FAREWELL: story.play("farewell")
		Phase.COMPLETE:
			if not world.voyage.departed: _depart()
