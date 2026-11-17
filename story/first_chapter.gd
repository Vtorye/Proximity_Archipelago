class_name FirstChapter
extends Node
## Coordinates one authored chapter. Gameplay services retain ownership of their operations.

signal focus_requested(cell: Vector2i)
signal demolition_requested(cell: Vector2i)
signal presentation_changed
signal checkpoint_requested(path: String)

enum Stage { INTRO, FOOD, FREE_BUILD, PLANNER, DEMOLITION, EXECUTION, WORK, TRANSPORT, RECRUIT, MAGIC, SUPPLIES, ATTACK, ESCORT, FAREWELL, COMPLETE }
const CHECKPOINT := "user://first_island_checkpoint.save"
var world: World
var story: StoryOverlay
var rules: FirstChapterRules
var stage := Stage.INTRO
var wish_index := 0
var created: Array[Dictionary] = []
var read_topics: Array[String] = []
var first_reprimand_seen := false
var _reprimanding := false
var _topic := false
var _scripted := false
var _elapsed := 0.0
var _worker: AntAgent
var _worked := false
var _transport_delivered := 0
var _recruited := false
var _attack_started := false
var _starting := true

func configure(colony: World, dialogue: StoryOverlay) -> void:
	world = colony
	story = dialogue
	rules = world.chapter_rules
	world.chapter = self
	world.match_controller.countdown_suspended = true
	world.match_controller.task_mode = true
	world.build_controller.placement_allowed = allows_placement
	world.voyage.requires_evacuation = true
	story.characters = rules.characters
	story.dialogue_resource = rules.dialogue
	story.action_requested.connect(_on_action)
	story.scene_finished.connect(_on_scene_finished)
	world.build_controller.built.connect(_on_built)
	world.population.spawned.connect(_on_spawned)
	world.logistics.shipment_delivered.connect(_on_shipment_delivered)
	world.queen.navigation = world.route_service
	world.queen.map = world.map
	world.queen.health = world.queen.maximum_health
	world.queen.arrived.connect(_on_queen_arrived)
	world.queen.died.connect(world.match_controller.lose_colony)
	world.combat.priority_target = world.queen
	world.combat.automatic_waves = false
	set_process(false)

func start(saved: Dictionary = {}) -> void:
	if not saved.is_empty():
		restore_state(saved)
	_starting = false
	set_process(true)
	if saved.is_empty():
		story.play("intro")
	else:
		_resume()

func economy_visible() -> bool:
	return stage >= Stage.EXECUTION

func nest_available() -> bool:
	return stage >= Stage.TRANSPORT

func allows_section(section: StringName) -> bool:
	return section == &"build" and stage in [Stage.FREE_BUILD, Stage.SUPPLIES, Stage.ATTACK] or section == &"colony" and economy_visible()

func allows_tool(option: BuildOption, _order: TaskBuildOrder = null) -> bool:
	if _scripted:
		return true
	if option == null:
		return false
	if story.is_modal:
		return false
	if stage == Stage.FREE_BUILD:
		return option == rules.road or wish_index < rules.wishes.size() and option == rules.wishes[wish_index]
	if stage == Stage.SUPPLIES:
		return option != rules.ship and option != rules.base_nest
	if stage == Stage.ATTACK:
		return option == rules.ship or option == rules.road
	return false

func allows_placement(option: BuildOption, cell: Vector2i, order: TaskBuildOrder = null) -> bool:
	if _scripted:
		return true
	if not allows_tool(option, order):
		return false
	if option == rules.ship:
		return cell == rules.ship_cell and ship() == null
	if stage == Stage.FREE_BUILD and option == rules.road:
		return not rules.route_cells.has(cell) and not _is_road(cell)
	return true

func preferred_option() -> StringName:
	if stage == Stage.FREE_BUILD and wish_index < rules.wishes.size():
		return rules.wishes[wish_index].id
	if stage == Stage.ATTACK:
		return rules.ship.id if ship() == null else rules.road.id
	return &""

func guide_cell() -> Vector2i:
	if stage == Stage.DEMOLITION and not created.is_empty():
		return created[0].cell
	if stage == Stage.ATTACK:
		if ship() == null:
			return rules.ship_cell
		for cell in rules.route_cells:
			if not _is_road(cell):
				return cell
	return Vector2i(2147483647, 2147483647)

func reprimand(_reason: StringName = &"action") -> void:
	if story.is_modal:
		return
	if not first_reprimand_seen:
		first_reprimand_seen = true
		_reprimanding = true
		story.play("first_reprimand")
	else:
		story.flash_warning("ui.chapter.wrong_action")

func talk(character: StoryCharacter) -> void:
	if story.is_modal or stage in [Stage.DEMOLITION, Stage.ESCORT, Stage.COMPLETE] or not topic_available(character):
		return
	read_topics.append(str(character.id))
	_topic = true
	story.play(str(character.topic))
	presentation_changed.emit()

func topic_available(character: StoryCharacter) -> bool:
	if character.id == &"Planner":
		return stage == Stage.FREE_BUILD and not read_topics.has(str(character.id))
	return (character.id in [&"Queen", &"Protagonist"] or stage >= Stage.WORK) and not read_topics.has(str(character.id))

func ship() -> CargoShip:
	for building in world.registry.all():
		if building is CargoShip:
			return building
	return null

func status_text() -> String:
	match stage:
		Stage.FREE_BUILD:
			return tr("ui.chapter.wish") % [wish_index + 1, rules.wishes.size(), tr(rules.wishes[mini(wish_index, rules.wishes.size() - 1)].display_name)]
		Stage.SUPPLIES:
			var lines: PackedStringArray = [tr("ui.chapter.stock_goal")]
			for item in preparation_cost():
				lines.append("%s %d / %d" % [tr(item.type.display_name), world.inventory.available(item.type), item.amount])
			return "\n".join(lines)
		Stage.ATTACK, Stage.ESCORT:
			var boat := ship()
			var lines: PackedStringArray = [tr("ui.chapter.evacuate_goal")]
			if boat == null:
				lines.append(tr("ui.chapter.build_ship"))
			else:
				for item in rules.minimum_cargo:
					lines.append("%s %d / %d (%d)" % [tr(item.type.display_name), boat.manifest.get(str(item.type.id), 0), item.amount, rules.cargo_capacity])
				if world.queen.route_to(landing_cell()).is_empty():
					lines.append(tr("ui.chapter.road_missing"))
			return "\n".join(lines)
		Stage.FOOD: return tr("ui.chapter.observe_food")
		Stage.WORK: return tr("ui.chapter.observe_work")
		Stage.TRANSPORT: return tr("ui.chapter.observe_transport")
		Stage.RECRUIT: return tr("ui.chapter.recruit_goal")
		Stage.DEMOLITION: return tr("ui.chapter.demolition_goal")
	return ""

func landing_cell() -> Vector2i:
	return rules.route_cells.back()

func can_evacuate() -> bool:
	var boat := ship()
	return stage == Stage.ATTACK and not world.match_controller.is_finished() and world.queen.health > 0 and boat != null and boat.supplied() and not world.queen.route_to(landing_cell()).is_empty()

func evacuate() -> void:
	if can_evacuate() and world.queen.depart(landing_cell()):
		stage = Stage.ESCORT
		story.show_hint("ui.chapter.escort_hint")
		focus_requested.emit(world.route_service.world_to_cell(world.queen.global_position))

func preparation_cost() -> Array[ResourceAmount]:
	var totals: Dictionary[ResourceType, int] = {}
	for item in rules.minimum_cargo:
		totals[item.type] = item.amount
	for item in world.build_controller.price(rules.ship, rules.ship_cell):
		totals[item.type] = totals.get(item.type, 0) + item.amount
	for cell in rules.route_cells:
		if not _is_road(cell):
			for item in world.build_controller.price(rules.road, cell):
				totals[item.type] = totals.get(item.type, 0) + item.amount
	var food := world.inventory.type_by_id(&"food")
	totals[food] = totals.get(food, 0) + rules.food_reserve
	var result: Array[ResourceAmount] = []
	for type in totals:
		var item := ResourceAmount.new()
		item.type = type
		item.amount = totals[type]
		result.append(item)
	return result

func _is_road(cell: Vector2i) -> bool:
	var terrain := world.map.surface_at(cell) as TerrainType
	return terrain != null and terrain.kind == TerrainType.Kind.ROAD

func _on_action(action: StringName) -> void:
	_elapsed = 0.0
	match action:
		&"food":
			stage = Stage.FOOD
			_prepare_worker()
			if _worker != null:
				_worker.needs.satiety = _worker.needs.capacity * 0.25
				_worker._seek_food()
		&"free":
			stage = Stage.FREE_BUILD
			for option in rules.wishes:
				world.build_controller.unlock_option(option)
		&"demolish": stage = Stage.DEMOLITION
		&"work":
			stage = Stage.WORK
			_worked = false
			_prepare_worker()
			checkpoint_requested.emit(SessionSave.PATH)
		&"transport":
			stage = Stage.TRANSPORT
			var depot := _demonstration_depot()
			if depot != null:
				depot.request("wood", 6)
				focus_requested.emit(depot.cell)
		&"recruit": stage = Stage.RECRUIT
		&"magic":
			stage = Stage.MAGIC
			_perform_magic()
		&"supplies":
			stage = Stage.SUPPLIES
			checkpoint_requested.emit(SessionSave.PATH)
		&"attack":
			stage = Stage.ATTACK
			_start_attack()
		&"depart":
			stage = Stage.COMPLETE
			_depart()
	presentation_changed.emit()

func _on_scene_finished() -> void:
	if _reprimanding or _topic:
		_reprimanding = false
		_topic = false
		_resume_hint()
		return
	_resume_hint()

func _resume_hint() -> void:
	story.show_hint("")

func _on_built(option: BuildOption, cell: Vector2i) -> void:
	if _starting or _scripted:
		return
	if stage == Stage.FREE_BUILD:
		created.append({"id": str(option.id), "cell": cell})
		if wish_index < rules.wishes.size() and option == rules.wishes[wish_index]:
			wish_index += 1
			if wish_index == rules.wishes.size():
				stage = Stage.PLANNER
				story.play.call_deferred("planner")
				presentation_changed.emit()
	if option == rules.ship:
		_configure_ship()

func _on_spawned(ant: AntAgent) -> void:
	if stage == Stage.RECRUIT and not _starting and ant.role == AntAgent.Role.WORKER:
		_recruited = true
		focus_requested.emit(world.route_service.world_to_cell(ant.global_position))

func _prepare_worker() -> void:
	_worker = null
	for ant in world.population.agents():
		if ant.story_id == &"Worker":
			_worker = ant
			break
	for ant in world.population.agents():
		if _worker != null:
			break
		if ant.role == AntAgent.Role.WORKER:
			_worker = ant
			ant.story_id = &"Worker"
			break
	if _worker != null:
		if not _worker.work_completed.is_connected(_on_work_completed):
			_worker.work_completed.connect(_on_work_completed)
		focus_requested.emit(world.route_service.world_to_cell(_worker.global_position))

func _on_work_completed(_ant: Node2D, _workplace: Node2D) -> void:
	_worked = true

func _on_shipment_delivered(target: Building, type: ResourceType, amount: int) -> void:
	if stage == Stage.TRANSPORT and target == _demonstration_depot() and type.id == &"wood":
		_transport_delivered += amount

func _demonstration_depot() -> House:
	var nests := world.logistics.nests()
	return nests[1] if nests.size() > 1 else null

func _process(delta: float) -> void:
	if _starting or story.is_modal or get_tree().paused or world.match_controller.is_finished():
		return
	_elapsed += delta
	match stage:
		Stage.FOOD:
			if is_instance_valid(_worker) and _worker.status == AntAgent.Status.EATING:
				story.play("worker_hello")
			elif _elapsed > rules.demonstration_timeout:
				_elapsed = 0.0
				_prepare_worker()
				if _worker != null:
					_worker._seek_food()
		Stage.DEMOLITION:
			if _elapsed >= rules.demolition_interval:
				_elapsed = 0.0
				_demolish_next()
		Stage.WORK:
			if is_instance_valid(_worker) and _worked and _worker.status == AntAgent.Status.HOME and _worker.transport.cargo.is_empty():
				story.play("logistics")
			elif not is_instance_valid(_worker):
				_prepare_worker()
		Stage.TRANSPORT:
			if _transport_delivered >= 6:
				story.play("recruit")
		Stage.RECRUIT:
			if _recruited:
				story.play("magic")
		Stage.SUPPLIES:
			if preparation_cost().all(func(item: ResourceAmount): return world.inventory.available(item.type) >= item.amount):
				stage = Stage.ATTACK
				checkpoint_requested.emit(CHECKPOINT)
				story.play("attack")

func _demolish_next() -> void:
	if created.is_empty():
		stage = Stage.EXECUTION
		story.play("execution")
		presentation_changed.emit()
		return
	var record: Dictionary = created.front()
	focus_requested.emit(record.cell)
	_scripted = true
	demolition_requested.emit(record.cell)
	var removed := true
	if record.id == str(rules.road.id):
		world.build_controller.apply_surface(rules.ground, record.cell)
		world.route_service.update_cells([record.cell], world.registry.blocked_cells())
	elif world.build_controller.demolition_target(record.cell) != null:
		removed = world.build_controller.demolish_at(record.cell)
	_scripted = false
	if removed:
		created.pop_front()

func _perform_magic() -> void:
	_scripted = true
	world.build_controller.apply_surface(rules.ground, rules.magic_cell)
	world.route_service.update_cells([rules.magic_cell], world.registry.blocked_cells())
	var success := world.build_controller.try_build(rules.base_nest, rules.magic_cell)
	_scripted = false
	if success:
		focus_requested.emit(rules.magic_cell)
		story.play.call_deferred("supplies")
	else:
		story.show_hint("ui.chapter.magic_failed")

func _configure_ship() -> void:
	var boat := ship()
	if boat != null:
		boat.capacity_per_resource = rules.cargo_capacity
		boat.requirements = rules.minimum_cargo
		boat.accepting_cargo = true
		world.logistics.cargo_receiver = boat

func _start_attack() -> void:
	world.build_controller.unlock_option(rules.ship)
	if _attack_started:
		return
	_attack_started = true
	for building in world.registry.all():
		if building is DefenseBuilding:
			world.combat.restore_building_health(building, maxi(1, roundi(world.combat.maximum_health(building) * rules.defense_health_fraction)))
	for index in range(rules.spider_count):
		var point := world.chapter_spawn_points[index % world.chapter_spawn_points.size()]
		world.combat.spawn_spider(world.route_service.world_to_cell(point.global_position))
	focus_requested.emit(world.route_service.world_to_cell(world.chapter_spawn_points[0].global_position))
	presentation_changed.emit()

func _on_queen_arrived() -> void:
	stage = Stage.FAREWELL
	story.play("farewell")

func _depart() -> void:
	var boat := ship()
	if boat == null:
		return
	world.voyage.departure_manifest = boat.manifest.duplicate()
	world.voyage.travelling_characters.assign(["Queen", "Protagonist", "Courier", "Worker"])
	world.queen.hide()
	boat.accepting_cargo = false
	var tween := boat.create_tween()
	tween.tween_property(boat, "position:x", boat.position.x + world.route_service.cell_size() * 6.0, 1.0)
	await tween.finished
	world.voyage.complete_departure()

func capture_state() -> Dictionary:
	return {
		"version": 1, "stage": stage, "wish": wish_index, "created": created.duplicate(true),
		"topics": read_topics.duplicate(), "reprimand": first_reprimand_seen, "attack": _attack_started,
		"worked": _worked, "recruited": _recruited, "transport_delivered": _transport_delivered,
		"queen_position": world.queen.position, "queen_health": world.queen.health,
		"queen_walking": world.queen.walking,
	}

func restore_state(saved: Dictionary) -> void:
	stage = clampi(int(saved.get("stage", Stage.INTRO)), Stage.INTRO, Stage.COMPLETE)
	wish_index = clampi(int(saved.get("wish", 0)), 0, rules.wishes.size())
	created.assign(saved.get("created", []))
	read_topics.assign(saved.get("topics", []))
	first_reprimand_seen = saved.get("reprimand", false)
	_attack_started = saved.get("attack", false)
	_worked = saved.get("worked", false)
	_recruited = saved.get("recruited", false)
	_transport_delivered = saved.get("transport_delivered", 0)
	world.queen.position = saved.get("queen_position", world.queen.position)
	world.queen.health = saved.get("queen_health", world.queen.maximum_health)

func _resume() -> void:
	_configure_ship()
	match stage:
		Stage.INTRO: story.play("intro")
		Stage.PLANNER: story.play("planner")
		Stage.EXECUTION: story.play("execution")
		Stage.FOOD, Stage.WORK: _prepare_worker()
		Stage.MAGIC: _perform_magic()
		Stage.ATTACK:
			if not _attack_started:
				story.play("attack")
		Stage.ESCORT:
			world.queen.depart(landing_cell())
		Stage.FAREWELL: story.play("farewell")
		Stage.COMPLETE:
			if not world.voyage.departed:
				story.play("farewell")
	_resume_hint()
	presentation_changed.emit()
