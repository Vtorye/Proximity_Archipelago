class_name FirstChapter
extends Node
## Coordinates one authored chapter. Gameplay services retain ownership of their operations.

signal focus_requested(cell: Vector2i)
signal presentation_changed
signal checkpoint_requested(path: String)

enum Stage { INTRO, FOOD, FREE_BUILD, PLANNER, DEMOLITION, EXECUTION, WORK, TRANSPORT, RECRUIT, MAGIC, SUPPLIES, ATTACK, ESCORT, FAREWELL, COMPLETE, ROAD, ROYAL_ORDER, PAUSE_LESSON, CAMERA_LESSON, ZOOM_LESSON, TALK_LESSON, SECOND_ORDER, WORKER_ADVICE }
const CHECKPOINT := "user://first_island_checkpoint.save"
var world: World
var story: StoryOverlay
var rules: FirstChapterRules
var stage := Stage.INTRO
var wish_index := 0
var created: Array[Dictionary] = []
var read_topics: Array[String] = []
var first_reprimand_seen := false
var _scripted := false
var _transport_delivered := 0
var _transport_requested := false
var _recruited := false
var _attack_started := false
var _starting := true
var _pause_tried := false
var _pause_finished := false
var _camera_distance := 0.0
var _zoom_tried := false
var _first_choice: StringName

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
	story.scene_finished.connect(_resume_hint)
	story.practice_done_requested.connect(_on_practice_done)
	world.build_controller.built.connect(_on_built)
	world.build_controller.order_completed.connect(_on_order_completed)
	world.build_controller.changed.connect(_on_construction_changed)
	world.registry.removed.connect(_on_building_removed)
	world.population.spawned.connect(_on_spawned)
	world.logistics.shipment_delivered.connect(_on_shipment_delivered)
	world.logistics.export_delivered.connect(_on_export_delivered)
	world.queen.navigation = world.route_service
	world.queen.map = world.map
	world.queen.health = world.queen.maximum_health
	world.queen.arrived.connect(_on_queen_arrived)
	world.queen.died.connect(world.match_controller.lose_colony)
	world.combat.priority_target = world.queen
	world.combat.automatic_waves = false
	PauseController.pause_changed.connect(_on_pause_changed)
	set_process(false)

func save_layout_id() -> String:
	return "first_island"

func countdown_visible() -> bool:
	return false

func navigation_changed(_mode: int) -> void:
	pass

func guide_cells() -> Array[Vector2i]:
	return [guide_cell()]

func travellers() -> Array[String]:
	return ["Queen", "Protagonist", "Courier", "Worker"]

func start(saved: Dictionary = {}) -> void:
	if not saved.is_empty():
		restore_state(saved)
	_starting = false
	world.inventory.quantities_known = _materials_revealed()
	set_process(true)
	if saved.is_empty():
		story.play("intro")
	else:
		_resume()

func economy_visible() -> bool:
	return true

func nest_available() -> bool:
	return true

func shows_control(control: StringName) -> bool:
	match control:
		&"pause":
			return stage != Stage.INTRO
		&"zoom":
			return stage not in [Stage.INTRO, Stage.PAUSE_LESSON, Stage.CAMERA_LESSON]
		&"colony", &"talk":
			return shows_control(&"zoom") and stage != Stage.ZOOM_LESSON
		&"build", &"tasks":
			return allows_section(control)
		&"routes":
			return false
	return true

func allows_section(section: StringName) -> bool:
	return section == &"build" and stage in [Stage.ROAD, Stage.FREE_BUILD, Stage.DEMOLITION, Stage.WORK, Stage.MAGIC, Stage.SUPPLIES, Stage.ATTACK] or section == &"tasks" and stage in [Stage.ROYAL_ORDER, Stage.SECOND_ORDER] or section == &"talk" or section == &"colony"

func allows_order(task_id: StringName, variant_id: StringName) -> bool:
	if stage == Stage.ROYAL_ORDER:
		return task_id == rules.opening_order.id
	if stage == Stage.SECOND_ORDER:
		var order := world.tasks.order_from_ids(task_id, variant_id)
		return order != null and order.variant.building == _other_choice()
	return false

func allows_tool(option: BuildOption, _order: TaskBuildOrder = null) -> bool:
	if _scripted:
		return true
	if stage == Stage.DEMOLITION and not story.is_modal:
		return option == null or option == rules.ground
	if option == null:
		return false
	if story.is_modal:
		return false
	if stage == Stage.ROAD:
		return option == rules.road and _order == null
	if stage == Stage.ROYAL_ORDER:
		return _order != null and _order.task == rules.opening_order
	if stage == Stage.SECOND_ORDER:
		return _order != null and allows_order(_order.task.id, _order.variant.id)
	if stage == Stage.WORK:
		return option == rules.wishes[1]
	if stage == Stage.MAGIC:
		return option == rules.base_nest
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
	if stage == Stage.DEMOLITION:
		return not story.is_modal and not created.is_empty() and not _demolition_in_progress() and cell == created.front().cell and _record_exists(created.front()) and (option == null or option == rules.ground and created.front().id == str(rules.road.id))
	if not allows_tool(option, order):
		return false
	if stage == Stage.ROAD:
		return cell == rules.road_cell
	if stage == Stage.ROYAL_ORDER:
		return cell == rules.order_cell
	if stage == Stage.SECOND_ORDER:
		return cell == rules.followup_cell
	if stage == Stage.MAGIC:
		return cell == rules.magic_cell
	if option == rules.ship:
		return cell == rules.ship_cell and ship() == null
	if stage == Stage.FREE_BUILD and option == rules.road:
		return not rules.route_cells.has(cell) and not _is_road(cell)
	return true

func preferred_option() -> StringName:
	if stage == Stage.ROAD:
		return rules.road.id
	if stage == Stage.WORK:
		return rules.wishes[1].id
	if stage == Stage.MAGIC:
		return rules.base_nest.id
	if stage == Stage.FREE_BUILD and wish_index < rules.wishes.size():
		return rules.wishes[wish_index].id
	if stage == Stage.ATTACK:
		return rules.ship.id if ship() == null else rules.road.id
	return &""

func highlighted_control() -> StringName:
	if stage == Stage.PAUSE_LESSON:
		return &"pause"
	if stage == Stage.ZOOM_LESSON:
		return &"zoom_in"
	if stage in [Stage.TALK_LESSON, Stage.WORKER_ADVICE]:
		return &"talk"
	if stage in [Stage.ROYAL_ORDER, Stage.SECOND_ORDER]:
		return &"tasks"
	return &""

func _on_pause_changed(_paused: bool) -> void:
	if stage != Stage.PAUSE_LESSON or story.is_modal or _pause_finished:
		return
	if PauseController.is_manually_paused():
		_pause_tried = true
		_resume_hint()
	elif _pause_tried:
		_pause_finished = true
		story.play.call_deferred("after_pause")

func camera_panned(distance: float) -> void:
	if stage == Stage.CAMERA_LESSON and not story.is_modal and distance > 0.0:
		_camera_distance += distance
		_refresh_practice_button()

func camera_zoomed(_level: int) -> void:
	if stage == Stage.ZOOM_LESSON and not story.is_modal:
		_zoom_tried = true
		_refresh_practice_button()

func _begin_camera_lesson(lesson: Stage) -> void:
	stage = lesson
	_camera_distance = 0.0
	_zoom_tried = false

func _refresh_practice_button() -> void:
	var practicing := stage in [Stage.CAMERA_LESSON, Stage.ZOOM_LESSON]
	var tried := _camera_distance >= rules.camera_pan_distance if stage == Stage.CAMERA_LESSON else _zoom_tried
	story.set_practice_done(practicing, practicing and tried)

func _on_practice_done() -> void:
	if story.is_modal or stage not in [Stage.CAMERA_LESSON, Stage.ZOOM_LESSON]:
		return
	if stage == Stage.CAMERA_LESSON and _camera_distance < rules.camera_pan_distance:
		return
	if stage == Stage.ZOOM_LESSON and not _zoom_tried:
		return
	var next_scene := "after_movement" if stage == Stage.CAMERA_LESSON else "after_zoom"
	stage = Stage.INTRO
	_refresh_practice_button()
	story.play.call_deferred(next_scene)

func guide_cell() -> Vector2i:
	if stage == Stage.ROAD:
		return rules.road_cell
	if stage == Stage.ROYAL_ORDER:
		return rules.order_cell
	if stage == Stage.SECOND_ORDER:
		return rules.followup_cell
	if stage == Stage.TRANSPORT:
		var depot := _demonstration_depot()
		return depot.cell if depot != null else rules.queen_cell
	if stage == Stage.WORK:
		for workplace in world.registry.workplaces():
			if workplace.improvement == null and workplace.matches_improvement(rules.wishes[1]):
				return workplace.cell
	if stage == Stage.MAGIC:
		return rules.magic_cell
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
		story.play("first_reprimand")
	else:
		story.flash_warning("ui.chapter.wrong_action")

func talk(character: StoryCharacter) -> void:
	if story.is_modal or stage in [Stage.DEMOLITION, Stage.ESCORT, Stage.COMPLETE] or not topic_available(character):
		return
	read_topics.append(str(character.id))
	story.play("road_advice" if stage == Stage.TALK_LESSON else "build_advice" if stage == Stage.WORKER_ADVICE else str(character.topic))
	presentation_changed.emit()

func topic_available(character: StoryCharacter) -> bool:
	if stage == Stage.TALK_LESSON:
		return character.id == &"Courier"
	if stage == Stage.WORKER_ADVICE:
		return character.id == &"Worker"
	if character.id == &"Worker":
		return stage in [Stage.FREE_BUILD, Stage.WORK, Stage.SUPPLIES] and not read_topics.has(str(character.id))
	if character.id == &"Planner":
		return stage == Stage.FREE_BUILD and not read_topics.has(str(character.id))
	return (character.id in [&"Queen", &"Protagonist"] or stage in [Stage.WORK, Stage.TRANSPORT, Stage.RECRUIT, Stage.MAGIC, Stage.SUPPLIES, Stage.ATTACK]) and not read_topics.has(str(character.id))

func ship() -> CargoShip:
	for building in world.registry.all():
		if building is CargoShip:
			return building
	return null

func status_text() -> String:
	match stage:
		Stage.PAUSE_LESSON: return tr("ui.story.controls.resume" if _pause_tried else "ui.story.controls.pause")
		Stage.CAMERA_LESSON: return tr("ui.story.controls.move")
		Stage.ZOOM_LESSON: return tr("ui.story.controls.zoom")
		Stage.TALK_LESSON: return tr("ui.story.controls.talk")
		Stage.ROAD: return tr("ui.story.tutorial.road_hint")
		Stage.ROYAL_ORDER: return tr("ui.story.tutorial.order_hint")
		Stage.SECOND_ORDER: return tr("ui.chapter.second_order") % tr(_other_choice().display_name)
		Stage.WORKER_ADVICE: return tr("ui.chapter.ask_worker")
		Stage.FREE_BUILD:
			return tr("ui.chapter.wish") % [wish_index + 1, rules.wishes.size(), tr(rules.wishes[mini(wish_index, rules.wishes.size() - 1)].display_name)]
		Stage.SUPPLIES:
			var lines: PackedStringArray = [tr("ui.chapter.stock_goal")]
			for item in preparation_cost():
				lines.append("%s %d / %d" % [tr(item.type.display_name), world.inventory.available(item.type), item.amount])
			return "\n".join(lines)
		Stage.ATTACK, Stage.ESCORT:
			var boat := ship()
			if boat == null:
				return tr("ui.chapter.build_ship")
			if world.queen.route_to(landing_cell()).is_empty():
				return tr("ui.chapter.road_missing")
			if can_evacuate():
				return tr("ui.chapter.board_ready")
			var lines: PackedStringArray = [tr("ui.chapter.evacuate_goal")]
			for item in rules.minimum_cargo:
				lines.append("%s %d / %d" % [tr(item.type.display_name), boat.manifest.get(str(item.type.id), 0), item.amount])
			return "\n".join(lines)
		Stage.WORK: return tr("ui.chapter.rebuild_sawmill")
		Stage.TRANSPORT: return tr("ui.chapter.wait_export") if _transport_requested else tr("ui.chapter.request_delivery")
		Stage.MAGIC: return tr("ui.chapter.place_base")
		Stage.RECRUIT: return tr("ui.chapter.recruit_goal")
		Stage.DEMOLITION: return tr("ui.chapter.demolition_wait" if _demolition_in_progress() else "ui.chapter.demolition_goal")
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
	match action:
		&"pause":
			stage = Stage.PAUSE_LESSON
		&"move_camera":
			_begin_camera_lesson(Stage.CAMERA_LESSON)
		&"zoom":
			_begin_camera_lesson(Stage.ZOOM_LESSON)
		&"talk":
			stage = Stage.TALK_LESSON
		&"road":
			stage = Stage.ROAD
			focus_requested.emit(rules.road_cell)
		&"order":
			stage = Stage.ROYAL_ORDER
			focus_requested.emit(rules.order_cell)
		&"second_order":
			stage = Stage.SECOND_ORDER
			focus_requested.emit(rules.followup_cell)
		&"worker_advice":
			stage = Stage.WORKER_ADVICE
		&"food":
			stage = Stage.ROAD
		&"free":
			stage = Stage.FREE_BUILD
			wish_index = maxi(wish_index, 1)
			for option in rules.wishes.slice(1):
				world.build_controller.unlock_option(option)
		&"demolish":
			stage = Stage.DEMOLITION
			_advance_demolition()
		&"work":
			stage = Stage.WORK
			world.build_controller.unlock_option(rules.wishes[1])
			checkpoint_requested.emit(SessionSave.PATH)
		&"transport":
			stage = Stage.TRANSPORT
			var depot := _demonstration_depot()
			if depot != null:
				if not depot.delivery_requested.is_connected(_on_delivery_requested):
					depot.delivery_requested.connect(_on_delivery_requested)
				focus_requested.emit(depot.cell)
		&"recruit": stage = Stage.RECRUIT
		&"magic":
			stage = Stage.MAGIC
			world.build_controller.unlock_option(rules.base_nest)
			focus_requested.emit(rules.magic_cell)
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
	_resume_hint()

func _resume_hint() -> void:
	story.show_hint(status_text())
	_refresh_practice_button()

func _on_built(option: BuildOption, cell: Vector2i) -> void:
	if _starting or _scripted:
		return
	if stage == Stage.ROAD and option == rules.road and cell == rules.road_cell:
		story.play.call_deferred("after_road")
	if stage == Stage.WORK and option == rules.wishes[1]:
		story.play.call_deferred("logistics")
	if stage == Stage.MAGIC and option == rules.base_nest:
		story.play.call_deferred("supplies")
	if stage == Stage.FREE_BUILD:
		created.append({"id": str(option.id), "cell": cell})
		if wish_index < rules.wishes.size() and option == rules.wishes[wish_index]:
			wish_index += 1
			if wish_index == rules.wishes.size():
				stage = Stage.PLANNER
				_reveal_materials()
				story.play.call_deferred("planner")
				presentation_changed.emit()
	if option == rules.ship:
		_configure_ship()
	_resume_hint()

func _on_order_completed(order: TaskBuildOrder) -> void:
	if stage == Stage.ROYAL_ORDER and order.task == rules.opening_order:
		_first_choice = order.variant.building.id
		created.append({"id": str(order.variant.building.id), "cell": rules.order_cell})
		story.play("ending_" + str(order.variant.id))
	elif stage == Stage.SECOND_ORDER and order.variant.building == _other_choice():
		created.append({"id": str(order.variant.building.id), "cell": rules.followup_cell})
		story.play("second_" + str(order.variant.building.id))

func _other_choice() -> BuildOption:
	for variant in rules.followup_order.variants:
		if variant.building.id != _first_choice:
			return variant.building
	return null

func _on_delivery_requested(resource_id: String, amount: int) -> void:
	if stage == Stage.TRANSPORT and resource_id == str(rules.delivery.type.id) and amount <= -rules.delivery.amount:
		_transport_requested = true
		_resume_hint()

func _on_spawned(ant: AntAgent) -> void:
	if stage == Stage.RECRUIT and not _starting and ant.role == AntAgent.Role.WORKER:
		_recruited = true
		focus_requested.emit(world.route_service.world_to_cell(ant.global_position))

func _on_shipment_delivered(_target: Building, _type: ResourceType, _amount: int) -> void:
	if stage == Stage.ATTACK:
		_resume_hint()

func _on_export_delivered(source: House, type: ResourceType, amount: int) -> void:
	if stage == Stage.TRANSPORT and _transport_requested and source == _demonstration_depot() and type == rules.delivery.type:
		_transport_delivered += amount

func _demonstration_depot() -> House:
	return world.registry.at(rules.delivery_cell) as House

func _process(_delta: float) -> void:
	if _starting or story.is_modal or get_tree().paused or world.match_controller.is_finished():
		return
	match stage:
		Stage.TRANSPORT:
			if _transport_requested and _transport_delivered >= rules.delivery.amount:
				story.play("recruit")
		Stage.RECRUIT:
			if _recruited:
				story.play("magic")
		Stage.SUPPLIES:
			if preparation_cost().all(func(item: ResourceAmount): return world.inventory.available(item.type) >= item.amount):
				stage = Stage.ATTACK
				checkpoint_requested.emit(CHECKPOINT)
				story.play("attack")

func _on_construction_changed() -> void:
	if not _starting and stage == Stage.DEMOLITION:
		_advance_demolition.call_deferred()

func _on_building_removed(_building: Building) -> void:
	_on_construction_changed()

func _record_exists(record: Dictionary) -> bool:
	if record.id == str(rules.road.id):
		return _is_road(record.cell)
	var building := world.registry.at(record.cell)
	if building is Workplace:
		return building.improvement != null and str(building.improvement.id) == record.id
	return building != null and building.option != null and str(building.option.id) == record.id

func _demolition_in_progress() -> bool:
	return not created.is_empty() and world.construction_service.at(created.front().cell, true) != null

func _advance_demolition() -> void:
	if stage != Stage.DEMOLITION:
		return
	while not created.is_empty() and not _record_exists(created.front()):
		created.pop_front()
	if created.is_empty():
		stage = Stage.EXECUTION
		story.play.call_deferred("execution")
		presentation_changed.emit()
	else:
		focus_requested.emit(created.front().cell)
		_resume_hint()

func _materials_revealed() -> bool:
	return stage in [Stage.PLANNER, Stage.DEMOLITION, Stage.EXECUTION, Stage.WORK, Stage.TRANSPORT, Stage.RECRUIT, Stage.MAGIC, Stage.SUPPLIES, Stage.ATTACK, Stage.ESCORT, Stage.FAREWELL, Stage.COMPLETE]

func _reveal_materials() -> void:
	var excess: Array[ResourceAmount] = []
	for limit in rules.revealed_supplies:
		var amount := maxi(0, world.inventory.available(limit.type) - limit.amount)
		if amount > 0:
			var cost := ResourceAmount.new()
			cost.type = limit.type
			cost.amount = amount
			excess.append(cost)
	world.inventory.try_spend_all(excess)
	world.inventory.quantities_known = true

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
	world.voyage.travelling_characters.assign(travellers())
	world.queen.hide()
	boat.accepting_cargo = false
	var tween := boat.create_tween()
	var offset := Vector2(rules.departure_offset_cells) * world.route_service.cell_size()
	tween.tween_property(boat, "position", boat.position + offset, rules.departure_seconds)
	await tween.finished
	world.voyage.complete_departure()

func capture_state() -> Dictionary:
	return {
		"version": 1, "stage": stage, "wish": wish_index, "created": created.duplicate(true),
		"topics": read_topics.duplicate(), "reprimand": first_reprimand_seen, "attack": _attack_started,
		"recruited": _recruited, "transport_delivered": _transport_delivered,
		"transport_requested": _transport_requested,
		"first_choice": str(_first_choice),
		"camera_distance": _camera_distance, "zoom_tried": _zoom_tried,
		"queen_position": world.queen.position, "queen_health": world.queen.health,
		"queen_walking": world.queen.walking,
	}

func restore_state(saved: Dictionary) -> void:
	stage = clampi(int(saved.get("stage", Stage.INTRO)), Stage.INTRO, Stage.WORKER_ADVICE)
	# Old versions used the food demonstration here. Continue those saves at the road lesson.
	if stage == Stage.FOOD:
		stage = Stage.ROAD
	wish_index = clampi(int(saved.get("wish", 0)), 0, rules.wishes.size())
	created.assign(saved.get("created", []))
	read_topics.assign(saved.get("topics", []))
	first_reprimand_seen = saved.get("reprimand", false)
	_attack_started = saved.get("attack", false)
	_recruited = saved.get("recruited", false)
	_transport_delivered = saved.get("transport_delivered", 0)
	_transport_requested = saved.get("transport_requested", false)
	_first_choice = StringName(saved.get("first_choice", "statue"))
	_camera_distance = maxf(0.0, float(saved.get("camera_distance", 0.0)))
	_zoom_tried = bool(saved.get("zoom_tried", false))
	world.queen.position = saved.get("queen_position", world.queen.position)
	world.queen.health = saved.get("queen_health", world.queen.maximum_health)

func _resume() -> void:
	_configure_ship()
	match stage:
		Stage.INTRO: story.play("intro")
		Stage.PLANNER: story.play("planner")
		Stage.EXECUTION: story.play("execution")
		Stage.DEMOLITION:
			_advance_demolition()
		Stage.TRANSPORT:
			var depot := _demonstration_depot()
			if depot != null and not depot.delivery_requested.is_connected(_on_delivery_requested):
				depot.delivery_requested.connect(_on_delivery_requested)
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
