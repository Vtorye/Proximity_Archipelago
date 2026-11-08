extends RefCounted
## Real orders exercise pickup, delivery, assembly, cancellation, loss, and crown exemptions.
func _world(test: Node) -> World:
	var tiles: Array = []
	for x in range(9):
		for y in range(5): tiles.append([x, y, 3, 0, 0, 0])
	var world: World = LevelLayout.create_world({"version": 1, "tiles": tiles, "objects": [[0, 2, "build/base_nest"], [0, 3, "Food"]]})
	world.auto_start = false
	world.task_deck = null
	test.add_child(world)
	return world

func _advance(test: Node, world: World, seconds: float) -> void:
	for frame in range(roundi(seconds * 30)):
		for ant in world.population.agents(): ant._physics_process(1.0 / 30.0)
		if frame % 30 == 0: await test.get_tree().process_frame

func run(test: Node) -> void:
	var world: World = _world(test)
	var controller: BuildController = world.build_controller
	var service: ConstructionService = controller.construction
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var option: SceneBuildOption = load("res://game/building/options/house.tres").duplicate(true)
	option.costs = [test.entry(wood, 4), test.entry(stone, 2)]
	option.construction_seconds = 2.0
	controller.options.append(option)
	var cell := Vector2i(3, 2)
	var before: int = world.inventory.quantity(wood)
	test.expect(controller.try_build(option, cell), "ordinary construction accepts a funded order")
	var site := world.registry.at(cell) as ConstructionSite
	test.expect(site != null and world.population.count() == 5, "an ordered house is a site with no new residents")
	test.expect(world.inventory.quantity(wood) == before - 4 and site.material_count() == 0 and not site.supplied(), "materials are earmarked at the base, never teleported to the site")
	test.expect(not controller.try_build(option, cell), "a pending site reserves its footprint")
	var crown: SceneBuildOption = load("res://game/building/options/base_nest.tres")
	world.inventory.add(world.inventory.type_by_id(&"royal"), 1)
	test.expect(controller.try_build(crown, Vector2i(7, 2)) and world.registry.at(Vector2i(7, 2)) is House, "crown purchases remain operational immediately")
	await _advance(test, world, 0.2)
	test.expect(world.registry.at(cell) is ConstructionSite, "a house cannot finish before physical deliveries")
	await _advance(test, world, 25.0)
	test.expect(world.registry.at(cell) is House and service.sites.is_empty() and world.population.count() == 15, "couriers deliver every material then a worker assembles and opens the house")
	test.expect(world.inventory.quantity(wood) == before - 4, "delivery and assembly never charge the order a second time")
	world.free()
	await test.get_tree().process_frame

	world = _world(test)
	controller = world.build_controller
	service = controller.construction
	option = option.duplicate(true)
	controller.options.append(option)
	before = world.inventory.quantity(wood)
	controller.try_build(option, cell)
	site = service.at(cell)
	var carrier: AntAgent = world.population.agents().back()
	var job: ConstructionJob = service.claim(carrier)
	test.expect(job != null and not job.assembly and WorldInventory.cargo_size(job.materials) == 6, "an unsupplied site gives a carrier only a pickup claim up to its capacity")
	service.release(job)
	test.expect(site.transit.values().all(func(count: int) -> bool: return count == 0), "abandoned pickup returns its exclusive claim to the base crate")
	test.expect(controller.demolish_at(cell) and service.sites.is_empty() and world.inventory.quantity(wood) == before, "cancelling untouched construction refunds materials still at the base")
	await test.get_tree().process_frame
	test.expect(world.registry.at(cell) == null, "cancelled sites release their footprint")
	controller.try_build(option, cell)
	site = service.at(cell)
	job = service.claim(carrier)
	job.picked_up = true
	var paid: int = world.inventory.quantity(wood)
	service.release(job)
	job = service.claim(carrier)
	test.expect(world.inventory.quantity(wood) == paid - 4 and job != null, "lost construction cargo requires paid replacement instead of duplicating resources")
	job.picked_up = true
	controller.demolish_at(cell)
	carrier.construction.job = job
	test.expect(carrier.construction.resume() and carrier.cargo.size() == 2, "a courier carrying cancelled materials physically returns them to storage")
	await _advance(test, world, 20)
	test.expect(carrier.cargo.is_empty(), "cancelled carried materials finish normal warehouse delivery")
	world.free()
	await test.get_tree().process_frame

	world = _world(test)
	controller = world.build_controller
	service = controller.construction
	controller.options.append(option)
	controller.try_build(option, cell)
	site = service.at(cell)
	for item in site.required: site.delivered[item.type.id] = item.amount
	carrier = world.population.agents().back()
	job = service.claim(carrier)
	test.expect(job != null and job.assembly and site.builder == carrier, "a carrier assembles a fully supplied site")
	service.release(job)
	world.free()
	await test.get_tree().process_frame

	world = _world(test)
	controller = world.build_controller
	var road: TileBuildOption = load("res://game/building/options/road.tres")
	before = world.inventory.quantity(wood)
	var map: TileMapLayer = world.get_node("Map")
	var old_atlas: Vector2i = map.get_cell_atlas_coords(cell)
	test.expect(controller.try_build(road, cell) and map.get_cell_atlas_coords(cell) == old_atlas, "roads use delivery and assembly before changing movement cost")
	var draft := BuildDraft.new()
	draft.controller = controller
	test.expect(draft.demolish(cell) and draft.commit() and controller.construction.sites.is_empty(), "the demolition brush cancels pending terrain construction")
	test.expect(world.inventory.quantity(wood) == before, "planned cancellation refunds only uncollected materials once")
	controller.try_build(road, cell)
	await _advance(test, world, 20)
	test.expect(map.get_cell_atlas_coords(cell) == road.atlas_coords and is_equal_approx(world.route_service.entry_cost(cell), 0.35), "finished roads update terrain and navigation")
	world.free()
	await test.get_tree().process_frame
