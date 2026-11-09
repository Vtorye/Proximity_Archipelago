class_name SessionSave
extends RefCounted
## Versioned, object-free snapshots. Replacements are atomic; the previous save remains a backup.
const PATH := "user://voyage.save"
const VERSION := 1
const LIMIT := 32 * 1024 * 1024

static func write(world: World, path := PATH) -> Error:
	if world == null or not world.ready_for_play or (world.match_controller.is_finished() and (world.voyage == null or not world.voyage.departed)): return ERR_UNAVAILABLE
	var bytes: PackedByteArray = var_to_bytes(capture(world))
	if bytes.size() > LIMIT: return ERR_OUT_OF_MEMORY
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(_digest(bytes))
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK: return error
	if FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(path, path + ".bak")
		if error != OK: return error
	return DirAccess.rename_absolute(path + ".tmp", path)

static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()

static func read(path := PATH) -> Dictionary:
	var data: Dictionary = _read_file(path)
	return _read_file(path + ".bak") if data.is_empty() else data

static func _read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 32 or file.get_length() > LIMIT + 32: return {}
	var digest: PackedByteArray = file.get_buffer(32)
	var content: PackedByteArray = file.get_buffer(file.get_length() - 32)
	if _digest(content) != digest: return {}
	var value: Variant = bytes_to_var(content)
	if not value is Dictionary or value.get("save_version") != VERSION: return {}
	if not value.get("layout") is Dictionary or not value.get("ants") is Array or not value.get("buildings") is Array or not value.get("stock") is Dictionary: return {}
	var probe: World = LevelLayout.create_world(value.layout)
	if probe == null: return {}
	var valid: bool = _valid_shape(value)
	probe.free()
	return value if valid else {}

static func _valid_shape(data: Dictionary) -> bool:
	if data.buildings.size() != data.layout.objects.size() or data.ants.size() > 10000: return false
	for key in ["options", "sites"]:
		if not data.get(key) is Array: return false
	for key in ["prices"]:
		if not data.get(key) is Dictionary: return false
	for key in ["amounts", "main", "transit"]:
		if not data.stock.get(key) is Dictionary: return false
	var remaining: Variant = data.get("time")
	if not (remaining is float or remaining is int) or not is_finite(remaining) or remaining < 0: return false
	for ant in data.ants:
		if not ant is Dictionary or not ant.get("home") is int or ant.home < 0 or ant.home >= data.buildings.size(): return false
		if not ant.get("position") is Vector2 or not ant.position.is_finite(): return false
		if not ant.get("role") is int or ant.role not in [0, 1, 2]: return false
		if not ant.get("cargo") is Array: return false
	for state in data.buildings:
		if not state is Dictionary: return false
	return true

static func amounts(items: Array) -> Array:
	var result: Array = []
	for item: ResourceAmount in items: result.append([str(item.type.id), item.amount])
	return result

static func unpack(items: Array, world: World) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	for row in items:
		var type: ResourceType = world.inventory.type_by_id(StringName(row[0]))
		if type == null: continue
		var item := ResourceAmount.new()
		item.type = type
		item.amount = int(row[1])
		result.append(item)
	return result

static func _properties(object: Object, names: Array) -> Dictionary:
	var result := {}
	for key in names: result[key] = object.get(key)
	return result

static func _set_properties(object: Object, data: Dictionary) -> void:
	for key in data: object.set(key, data[key])

static func capture(world: World) -> Dictionary:
	var buildings: Array[Node] = []
	for building in world.registry.all():
		if not building is ConstructionSite: buildings.append(building)
	for building: Building in buildings:
		if not building.has_meta(&"layout_kind"):
			building.set_meta(&"layout_kind", "build/" + str(building.option.id))
	var data := {"save_version": VERSION, "layout": LevelLayout.capture(world.get_node("Map"), buildings), "buildings": [], "ants": [], "sites": []}
	data.layout["wave_mode"] = world.combat != null
	data["stock"] = {"amounts": world.inventory._amounts.duplicate(), "main": world.inventory._main_stock.duplicate(), "transit": world.inventory._transit.duplicate()}
	data["time"] = world.match_controller.time_remaining
	data["finished"] = world.match_controller.is_finished()
	data["options"] = world.build_controller.options.map(func(option: BuildOption): return str(option.id))
	data["prices"] = {"multiplier": world.prices.global_multiplier, "counts": world.events._counts.duplicate()}
	for building: Building in buildings:
		var state := {}
		if building is House:
			state = _properties(building, ["auto_dispatch", "storage_capacity"])
			state["stock"] = world.inventory._depots.get(building, {}).duplicate()
		if building is Workplace:
			state = _properties(building, ["_yield_remainder"])
			state["output"] = amounts(building._pending_output)
		if building is DefenseBuilding: state["shot_timer"] = building.shot_timer
		if world.combat != null: state["health"] = world.combat.health(building)
		data.buildings.append(state)
	var sites: Array[ConstructionSite] = world.build_controller.construction.sites if world.build_controller.construction != null else [] as Array[ConstructionSite]
	for site in sites:
		var crates: Array = []
		for source in site.crates: crates.append([buildings.find(source), amounts(site.crates[source])])
		data.sites.append({"option": str(site.option.id), "cell": site.cell, "required": amounts(site.required), "delivered": site.delivered.duplicate(), "transit": site.transit.duplicate(), "progress": site.progress, "crates": crates})
	for ant in world.population.agents():
		var state: Dictionary = _properties(ant, ["role", "position", "speed", "work_time", "carry_capacity", "max_health", "health", "attack_damage", "status", "_destination", "_timer", "_carrying", "_shipment", "_main_delivery", "_last_direction", "_waiting_for_work", "_waiting_reason"])
		state["home"] = buildings.find(ant.home)
		state["satiety"] = ant.needs.satiety
		state["capacity"] = ant.needs.capacity
		state["cargo"] = amounts(ant.cargo)
		state["meal"] = ant._meal != null and ant._meal.active
		state["workplace"] = buildings.find(ant.current_workplace)
		state["pickup"] = buildings.find(ant._pickup_source)
		state["delivery"] = buildings.find(ant._delivery_nest)
		if ant._plan != null: state["foodless"] = ant._plan.foodless
		if ant.motion.route != null:
			state["route"] = ant.motion.route.cells.duplicate()
			state["route_index"] = ant.motion.route.current_index
			state["finished"] = ant.motion.finished
		if ant.construction != null and ant.construction.job != null:
			var job: ConstructionJob = ant.construction.job
			state["job"] = {"site": sites.find(job.site), "source": buildings.find(job.source), "materials": amounts(job.materials), "picked_up": job.picked_up, "assembly": job.assembly}
		if ant.combat != null:
			state["tower"] = buildings.find(ant.combat.tower)
			state["combat_attack"] = ant.combat._attack
		data.ants.append(state)
	if world.tasks != null:
		data["tasks"] = _properties(world.tasks, ["level", "closed", "completed_count", "skipped_count", "pending_reward", "buffs", "_speed", "difficulty_multiplier", "message"])
		data.tasks["slots"] = world.tasks.slots.map(func(task: TaskSpec): return str(task.id) if task != null else "")
		data.tasks["pool"] = world.tasks._pool.map(func(task: TaskSpec): return str(task.id))
		data.tasks["rng"] = world.tasks._rng.state
	if world.voyage != null: data["voyage"] = _properties(world.voyage, ["island", "seed_value", "score", "departed", "offers"])
	if world.combat != null:
		data["combat"] = {"number": world.combat.spawner.number, "remaining": world.combat.spawner.remaining, "interval": world.combat.rules.wave_interval_seconds, "spiders": [], "traps": world.combat.traps.keys()}
		for spider in world.combat.spiders:
			var state := _properties(spider, ["position", "health", "_attack", "_sabotage"])
			state["scene"] = spider.scene_file_path
			data.combat.spiders.append(state)
	return data

static func apply(world: World, data: Dictionary) -> void:
	# Restore into a fresh world before simulation begins. Old startup residents never consume saved stock.
	for ant in world.population.agents(): ant.free()
	var buildings: Array[Building] = world.registry.all()
	buildings.clear()
	for row in data.layout.objects: buildings.append(world.registry.at(Vector2i(row[0], row[1])))
	world.inventory._amounts.assign(data.stock.amounts)
	world.inventory._main_stock.assign(data.stock.main)
	world.inventory._transit.assign(data.stock.transit)
	world.inventory._reserved.clear()
	world.inventory._tickets.clear()
	for index in range(buildings.size()):
		var building: Building = buildings[index]
		var state: Dictionary = data.buildings[index].duplicate()
		if state.has("stock"):
			if world.inventory._depots.has(building): world.inventory._depots[building as House] = state.stock.duplicate()
			state.erase("stock")
		if state.has("output"):
			building._pending_output = unpack(state.output, world)
			state.erase("output")
		if state.has("health"):
			world.combat._health[building] = int(state.health)
			state.erase("health")
		_set_properties(building, state)
	var definitions := _definitions(world)
	world.build_controller.options.clear()
	for id in data.options:
		if definitions.has(id): world.build_controller.options.append(definitions[id])
	world.prices.definitions = world.build_controller.options.duplicate()
	world.prices.global_multiplier = data.prices.multiplier
	world.events._counts.assign(data.prices.counts)
	var sites: Array[ConstructionSite] = []
	for state in data.sites:
		var option: BuildOption = definitions[state.option]
		var candidate: Building
		if option is SceneBuildOption:
			candidate = option.scene.instantiate()
			candidate.setup(state.cell, option)
		var site := ConstructionSite.new()
		site.service = world.build_controller.construction
		site.candidate = candidate
		site.required = unpack(state.required, world)
		site.delivered.assign(state.delivered)
		site.transit.assign(state.transit)
		site.progress = state.progress
		site.setup(state.cell, option)
		for row in state.crates:
			if row[0] >= 0: site.crates[buildings[row[0]]] = unpack(row[1], world)
		site.position = world.buildings.to_local(world.route_service.cell_to_world(state.cell))
		world.buildings.add_child(site)
		world.build_controller.construction.sites.append(site)
		if option is SceneBuildOption: world.registry.register(site)
		world.prices.queue_order(option, 1)
		sites.append(site)
	world.route_service.rebuild(world.registry.blocked_cells())
	for saved in data.ants:
		var state: Dictionary = saved.duplicate()
		var home: House = buildings[state.home]
		var ant: AntAgent = world.population._create_resident(home, state.role)
		world.population._add_resident(home, ant)
		world.inventory.release(ant._meal)
		ant._meal = world.inventory.reserve(world.planner.food_type, 1, true) if state.meal else null
		ant.needs.capacity = state.capacity
		ant.needs.satiety = state.satiety
		ant.cargo = unpack(state.cargo, world)
		ant.current_workplace = buildings[state.workplace] if state.workplace >= 0 else null
		ant._pickup_source = buildings[state.pickup] if state.pickup >= 0 else null
		ant._delivery_nest = buildings[state.delivery] if state.delivery >= 0 else null
		if ant.current_workplace != null:
			ant.current_workplace.reserve_worker(ant)
			if state.status == AntAgent.Status.WORKING: ant.current_workplace.begin_work(ant)
			ant._plan = WorkPlan.new()
			ant._plan.workplace = ant.current_workplace
			ant._plan.foodless = state.get("foodless", false)
		if state.has("route"):
			var cells: Array[Vector2i] = []
			cells.assign(state.route)
			ant.motion.route = world.route_service.make_route(cells)
			ant.motion.route.current_index = state.route_index
			ant.motion.finished = state.finished
		if state.has("job"):
			var job := ConstructionJob.new()
			job.site = sites[state.job.site] if state.job.site >= 0 else null
			job.source = buildings[state.job.source] if state.job.source >= 0 else null
			job.materials = unpack(state.job.materials, world)
			job.picked_up = state.job.picked_up
			job.assembly = state.job.assembly
			ant.construction.job = job
			if job.assembly and job.live(): job.site.builder = ant
		if ant.combat != null: ant.combat._attack = state.get("combat_attack", 0.0)
		if state.get("tower", -1) >= 0:
			ant.combat.tower = buildings[state.tower]
			ant.combat.tower.gunner = ant
		for key in ["home", "satiety", "capacity", "cargo", "meal", "workplace", "pickup", "delivery", "foodless", "route", "route_index", "finished", "job", "tower", "combat_attack"]: state.erase(key)
		_set_properties(ant, state)
	if data.has("tasks"):
		var tasks: Dictionary = {}
		for stage in world.tasks.deck.stages:
			for task in stage.tasks: tasks[str(task.id)] = task
		var state: Dictionary = data.tasks.duplicate()
		world.tasks.slots.clear()
		for id in state.slots: world.tasks.slots.append(tasks.get(id))
		world.tasks._pool.clear()
		for id in state.pool: world.tasks._pool.append(tasks[id])
		world.tasks._rng.state = state.rng
		for key in ["slots", "pool", "rng"]: state.erase(key)
		_set_properties(world.tasks, state)
		world.tasks.changed.emit()
	if data.has("voyage"): _set_properties(world.voyage, data.voyage)
	if data.has("combat"):
		world.combat.spawner.number = data.combat.number
		world.combat.spawner.remaining = data.combat.remaining
		world.combat.rules = world.combat.rules.duplicate()
		world.combat.rules.wave_interval_seconds = data.combat.interval
		for state in data.combat.spiders:
			var spider: SpiderAgent = world.combat.spawn_spider(world.route_service.world_to_cell(world.combat.to_global(state.position)), state.get("scene", ""))
			if spider != null:
				var properties: Dictionary = state.duplicate()
				properties.erase("scene")
				_set_properties(spider, properties)
		for cell in data.combat.traps: world.combat.place_trap(cell)
	world.match_controller.start(world.inventory)
	world.match_controller.time_remaining = data.time
	world.inventory.changed.emit()
	world.population.changed.emit()
	if data.get("finished", false): world.match_controller.complete_objective()

static func _definitions(world: World) -> Dictionary:
	var result := {}
	var options: Array[BuildOption] = world.build_controller.options.duplicate()
	options.append(Voyage.SHIP)
	if world.tasks != null:
		options.append(world.tasks.deck.unlocked_road)
		for stage in world.tasks.deck.stages:
			for task in stage.tasks: options.append_array(task.unlocks)
	for option in options:
		if option != null: result[str(option.id)] = option
	return result
