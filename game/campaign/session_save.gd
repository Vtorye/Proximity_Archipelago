class_name SessionSave
extends RefCounted
## Versioned, object-free snapshots. Replacements are atomic; the previous save remains a backup.
const PATH := "user://voyage.save"
const VERSION := 1
const LIMIT := 32 * 1024 * 1024

static func write(world: World, path := PATH, tutorial: Dictionary = {}) -> Error:
	if world == null or not world.ready_for_play or (world.match_controller.is_finished() and (world.voyage == null or not world.voyage.departed)): return ERR_UNAVAILABLE
	var snapshot := capture(world)
	if not tutorial.is_empty():
		snapshot["tutorial"] = tutorial
	var bytes: PackedByteArray = var_to_bytes(snapshot)
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

static func capture(world: World) -> Dictionary:
	var buildings: Array[Building] = []
	for building in world.registry.all():
		if not building is ConstructionSite: buildings.append(building)
	for building: Building in buildings:
		if not building.has_meta(&"layout_kind"):
			building.set_meta(&"layout_kind", "build/" + str(building.option.id))
	var layout_buildings: Array[Node] = []
	layout_buildings.assign(buildings)
	var data := {"save_version": VERSION, "layout": LevelLayout.capture(world.map, layout_buildings), "buildings": [], "ants": [], "sites": []}
	if world.chapter != null:
		data["chapter"] = world.chapter.capture_state()
		data.layout["chapter"] = "first_island"
	data.layout["wave_mode"] = world.combat != null
	data["stock"] = world.inventory.capture_stock()
	data["time"] = world.match_controller.time_remaining
	data["finished"] = world.match_controller.is_finished()
	data["options"] = world.build_controller.options.map(func(option: BuildOption): return str(option.id))
	data["prices"] = world.prices.capture_state()
	for building: Building in buildings:
		var state := {}
		if building is House:
			# incoming is not saved: its carriers lose their order target on load.
			state = building.capture_storage_settings()
			state["stock"] = world.inventory.capture_depot(building)
		if building is Workplace:
			state = building.capture_production()
		if building is DefenseBuilding: state["shot_timer"] = building.shot_timer
		if building is CargoShip: state["manifest"] = building.manifest.duplicate()
		if world.combat != null: state["health"] = world.combat.health(building)
		data.buildings.append(state)
	var sites: Array[ConstructionSite] = world.build_controller.construction.sites if world.build_controller.construction != null else [] as Array[ConstructionSite]
	for site in sites:
		var crates: Array = []
		for source in site.crates: crates.append([buildings.find(source), ResourceAmount.pack(site.crates[source])])
		var saved := {"option": str(site.option.id), "cell": site.cell, "required": ResourceAmount.pack(site.required), "delivered": site.delivered.duplicate(), "transit": site.transit.duplicate(), "progress": site.progress, "crates": crates}
		if site.order != null:
			saved["task_id"] = str(site.order.task.id)
			saved["variant_id"] = str(site.order.variant.id)
		data.sites.append(saved)
	for ant in world.population.agents():
		data.ants.append(ant.capture_state(buildings, sites))
	if world.tasks != null:
		data["tasks"] = world.tasks.capture_state()
	if world.voyage != null: data["voyage"] = world.voyage.capture_state()
	if world.combat != null:
		data["combat"] = {"number": world.combat.spawner.number, "remaining": world.combat.spawner.remaining, "interval": world.combat.spawner.interval_seconds, "spiders": [], "traps": world.combat.traps.keys()}
		for spider in world.combat.spiders:
			data.combat.spiders.append(spider.capture_state())
	return data

static func apply(world: World, data: Dictionary) -> void:
	# Restore into a fresh world before simulation begins. Old startup residents never consume saved stock.
	for ant in world.population.agents(): ant.free()
	var buildings: Array[Building] = world.registry.all()
	buildings.clear()
	var layout: LevelData = LevelLayout.decode(data.layout)
	for placement in layout.objects:
		buildings.append(world.registry.at(placement.cell))
	world.inventory.restore_stock(data.stock)
	for index in range(buildings.size()):
		var building: Building = buildings[index]
		var state: Dictionary = data.buildings[index]
		if building is House:
			building.restore_storage_settings(state)
			world.inventory.restore_depot(building, state.get("stock", world.inventory.capture_depot(building)))
		elif building is CargoShip:
			building.manifest.assign(state.get("manifest", {}))
		elif building is Workplace:
			building.restore_production(state, ResourceAmount.unpack(state.output, world.inventory.type_by_id))
		elif building is DefenseBuilding:
			building.shot_timer = state.shot_timer
		if state.has("health"):
			world.combat.restore_building_health(building, int(state.health))
	var definitions := _definitions(world)
	var catalog_ids: Array[String] = []
	for option in world.build_controller.options:
		catalog_ids.append(str(option.id))
	if world.voyage_rules != null and world.voyage_rules.ship != null:
		catalog_ids.append(str(world.voyage_rules.ship.id))
	if world.tasks != null:
		var deck := world.tasks.deck
		if deck.unlocked_road != null:
			catalog_ids.append(str(deck.unlocked_road.id))
		for stage in deck.stages:
			for task in stage.tasks:
				for option in task.unlocks:
					catalog_ids.append(str(option.id))
	var options: Array[BuildOption] = []
	for id in data.options:
		if catalog_ids.has(id) and definitions.has(id):
			options.append(definitions[id])
	if world.chapter_rules != null:
		for option in world.chapter_rules.wishes:
			if data.options.has(str(option.id)) and not options.has(option):
				options.append(option)
	world.build_controller.set_available_options(options)
	world.prices.restore_state(data.prices)
	var legacy_order: TaskBuildOrder
	if data.has("tasks") and world.tasks != null:
		world.tasks.restore_state(data.tasks)
		var legacy_id: String = data.tasks.get("active_order_id", "")
		if not legacy_id.is_empty():
			legacy_order = _saved_order(world.tasks, legacy_id, &"diversion" if data.tasks.get("active_order_diversion", false) else &"build")
	var sites: Array[ConstructionSite] = []
	for state in data.sites:
		var option: BuildOption = definitions[state.option]
		var order: TaskBuildOrder
		if world.tasks != null and state.has("task_id"):
			order = _saved_order(world.tasks, state.task_id, state.get("variant_id", ""))
		elif legacy_order != null and legacy_order.variant.building.id == StringName(state.option):
			order = legacy_order
			legacy_order = null
		if order != null:
			if order.variant.building.id == StringName(state.option):
				option = order.variant.building
			else:
				order = null
		var candidate: Building
		if option is SceneBuildOption:
			candidate = option.scene.instantiate()
			candidate.colony_owned = true
			candidate.setup(state.cell, option)
		var site: ConstructionSite = world.build_controller.construction.instantiate_site()
		site.order = order
		site.candidate = candidate
		site.required = ResourceAmount.unpack(state.required, world.inventory.type_by_id)
		site.delivered.assign(state.delivered)
		site.transit.assign(state.transit)
		site.progress = state.progress
		site.setup(state.cell, option)
		for row in state.crates:
			if row[0] >= 0: site.crates[buildings[row[0]]] = ResourceAmount.unpack(row[1], world.inventory.type_by_id)
		site.position = world.buildings.to_local(world.route_service.cell_to_world(state.cell))
		world.buildings.add_child(site)
		world.build_controller.construction.sites.append(site)
		if option is SceneBuildOption: world.registry.register(site)
		world.prices.queue_order(option, 1)
		sites.append(site)
	world.route_service.rebuild(world.registry.blocked_cells())
	if world.chapter_rules != null:
		for building in buildings:
			if building is CargoShip:
				building.requirements = world.chapter_rules.minimum_cargo
				building.accepting_cargo = true
				building.capacity_per_resource = world.chapter_rules.cargo_capacity
				world.logistics.cargo_receiver = building
	for state in data.ants:
		var home: House = buildings[state.home]
		var ant: AntAgent = world.population.restore_resident(home, state.role)
		if ant != null:
			ant.restore_state(state, buildings, sites)
	if data.has("voyage"): world.voyage.restore_state(data.voyage)
	if data.has("combat"):
		world.combat.spawner.number = data.combat.number
		world.combat.spawner.remaining = data.combat.remaining
		world.combat.spawner.interval_seconds = data.combat.interval
		for state in data.combat.spiders:
			var spider: SpiderAgent = world.combat.spawn_spider(world.route_service.world_to_cell(world.combat.to_global(state.position)), state.get("scene", ""))
			if spider != null:
				spider.restore_state(state)
		for cell in data.combat.traps: world.combat.place_trap(cell)
	world.match_controller.start(world.inventory)
	world.match_controller.time_remaining = data.time
	world.inventory.changed.emit()
	world.population.changed.emit()
	if data.get("finished", false): world.match_controller.complete_objective()

static func _saved_order(director: TaskDirector, task_id: String, variant_id: StringName) -> TaskBuildOrder:
	return director.order_from_ids(director.deck.legacy_task_ids.get(task_id, task_id), variant_id)

static func _definitions(world: World) -> Dictionary:
	var result := {}
	var options: Array[BuildOption] = world.build_controller.options
	if world.chapter_rules != null:
		options.append_array(world.chapter_rules.wishes)
		options.append(world.chapter_rules.ship)
		options.append(world.chapter_rules.base_nest)
	if world.voyage_rules != null:
		options.append(world.voyage_rules.ship)
	if world.tasks != null:
		options.append(world.tasks.deck.unlocked_road)
		for task in world.tasks.deck.requests:
			for variant in task.variants:
				if variant != null: options.append(variant.building)
			options.append_array(task.unlocks)
		for stage in world.tasks.deck.stages:
			for task in stage.tasks:
				for variant in task.variants:
					if variant != null: options.append(variant.building)
				options.append_array(task.unlocks)
	for option in options:
		if option != null: result[str(option.id)] = option
	return result
