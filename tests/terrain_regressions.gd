extends RefCounted
## Soil rules share the same ground state through roads, authoring, quotes, and physical construction.
func _world(test: Node, physical := false) -> World:
	var tiles: Array = []
	for x in range(14):
		for y in range(8): tiles.append([x, y, 3, 0, 0, 0])
	for index in range(5):
		var cell := Vector2i(2 + index * 2, 2)
		tiles[cell.x * 8 + cell.y] = [cell.x, cell.y, 5 + index, 0, 0, 0]
	var world: World = LevelLayout.create_world({"version": 1, "tiles": tiles, "objects": [[0, 0, "build/base_nest"], [0, 1, "Food"]]})
	world.auto_start = false
	world.build_controller.physical_construction = physical
	world.prices.task_deck = null
	test.add_child(world)
	return world

func run(test: Node) -> void:
	await _placement_and_prices(test)
	await _yield(test)
	await _capacity(test)
	await _underlays(test)
	await _physical_build(test)
	await _authoring(test)
	_texture_replacement(test)

func _placement_and_prices(test: Node) -> void:
	var world: World = _world(test)
	var controller: BuildController = world.build_controller
	var road: BuildOption = load("res://game/building/options/road.tres")
	var berry: BuildOption = load("res://game/building/options/apple_tree.tres")
	var house: BuildOption = load("res://game/building/options/house.tres")
	var matrix := [[true, true, true], [false, true, false], [true, true, true], [true, true, false], [true, false, false]]
	for index in range(5):
		for kind in range(3):
			var option: BuildOption = [road, berry, house][kind]
			test.expect(controller.placement_check(option, Vector2i(2 + index * 2, 2)).allowed() == matrix[index][kind], "terrain permission matrix %d/%d" % [index, kind])
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var dry := Vector2i(6, 2)
	var sand := Vector2i(10, 2)
	test.expect(BuildController.price_amount(controller.price(house, dry), wood) == 7 and BuildController.price_amount(controller.price(house, dry), stone) == 14, "dry ground discounts both nest materials by thirty percent")
	test.expect(BuildController.price_amount(controller.price(road, sand), wood) == 2, "sand multiplies the road price before rounding whole materials up")
	var draft := BuildDraft.new()
	draft.controller = controller
	draft.paint(house, dry)
	draft.paint(road, sand)
	test.expect(BuildController.price_amount(draft.costs(), wood) == 9 and BuildController.price_amount(draft.costs(), stone) == 14, "the plan shares cell-specific prices with individual construction checks")
	var before: int = world.inventory.quantity(wood)
	test.expect(draft.commit() and world.inventory.quantity(wood) == before - 9 and world.registry.at(dry) is House, "one committed plan charges each terrain modifier exactly once")
	var map := world.get_node("Map") as TerrainMap
	test.expect(map.ground_at(sand).id == &"sand", "paving preserves the sand beneath its road")
	var ground: BuildOption = load("res://game/building/options/ground.tres")
	test.expect(controller.placement_check(ground, Vector2i(4, 2)).code == PlacementCheck.Code.ALREADY_PLACED, "ordinary soil cannot erase rocky restrictions")
	test.expect(controller.placement_check(road, Vector2i(-1, -1)).code == PlacementCheck.Code.OUTSIDE_MAP, "outside-map feedback remains distinct from forbidden soil")
	world.free()
	await test.get_tree().process_frame

func _source(world: World, cell: Vector2i, output: ResourceType) -> Workplace:
	var source := Workplace.new()
	source.output = output
	source.setup(cell, null)
	source.position = world.buildings.to_local(world.route_service.cell_to_world(cell))
	world.buildings.add_child(source)
	world.registry.register(source)
	return source

func _yield(test: Node) -> void:
	var world: World = _world(test)
	var food: ResourceType = world.inventory.type_by_id(&"food")
	var worker := Node2D.new()
	for sample in [[Vector2i(2, 2), 6], [Vector2i(6, 2), 3], [Vector2i(4, 2), 4]]:
		var source: Workplace = _source(world, sample[0], food)
		source.reserve_worker(worker)
		var produced := 0
		for cycle in range(4):
			source.complete_cycle(worker, true)
			var batch: Array[ResourceAmount] = source.take_output(100)
			if cycle == 0: test.expect(not batch.is_empty(), "even dry-soil bushes yield on their first complete cycle")
			produced += WorldInventory.cargo_size(batch)
		test.expect(produced == sample[1], "fractional soil yield is exact across four cycles")
	var timber: Workplace = _source(world, Vector2i(2, 3), world.inventory.type_by_id(&"wood"))
	(world.get_node("Map") as TerrainMap).paint_tile(timber.cell, Vector4i(5, 0, 0, 0), true)
	world.terrain.refresh_all()
	test.expect(timber.terrain_yield_multiplier == 1, "fertility applies to raw berries, not timber or other production")
	var finite: Workplace = _source(world, Vector2i(2, 4), food)
	(world.get_node("Map") as TerrainMap).paint_tile(finite.cell, Vector4i(5, 0, 0, 0), true)
	world.terrain.refresh_all()
	finite.finite_supply = true
	finite.remaining_supply = 2
	finite.reserve_worker(worker)
	finite.complete_cycle(worker, true)
	test.expect(finite.remaining_supply == 0 and WorldInventory.cargo_size(finite.take_output(100)) == 2, "a boosted finite harvest conserves the last physical berries")
	worker.free()
	world.free()
	await test.get_tree().process_frame

func _capacity(test: Node) -> void:
	var world: World = _world(test)
	var map := world.get_node("Map") as TerrainMap
	var home: House = world.logistics.main_nest
	map.paint_tile(Vector2i(1, 1), Vector4i(8, 0, 0, 0), true)
	world.terrain.refresh_all()
	test.expect(home.resident_limit() == 25, "diagonally adjacent wet ground grants a base twenty-five resident slots")
	map.paint_tile(Vector2i(1, 0), Vector4i(8, 0, 0, 0), true)
	world.terrain.refresh_all()
	test.expect(home.resident_limit() == 25, "multiple wet neighbors do not stack capacity bonuses")
	world.inventory.add(world.inventory.type_by_id(&"food"), 200)
	while home.residents.size() < 25:
		if not world.population.recruit(home, AntAgent.Role.WORKER): break
	test.expect(home.residents.size() == 25 and not world.population.can_recruit(home, AntAgent.Role.WORKER), "recruitment honors the increased maximum and its final slot")
	for cell in [Vector2i(1, 0), Vector2i(1, 1)]: map.paint_tile(cell, Vector4i(3, 0, 0, 0), true)
	world.terrain.refresh_all()
	test.expect(home.resident_limit() == 20 and home.residents.size() == 25 and not home.has_space(), "losing wet ground stops further recruitment without killing existing residents")
	world.build_controller.try_build(load("res://game/building/options/house.tres"), Vector2i(7, 2))
	var barracks := world.registry.at(Vector2i(7, 2)) as House
	test.expect(barracks != null and barracks.resident_limit() == 6 and barracks.residents.size() == 5, "a nearby wet tile increases barracks capacity without spawning free extra ants")
	world.free()
	await test.get_tree().process_frame

func _underlays(test: Node) -> void:
	var world: World = _world(test)
	var map := world.get_node("Map") as TerrainMap
	var cell := Vector2i(2, 2)
	var road: BuildOption = load("res://game/building/options/road.tres")
	world.build_controller.try_build(road, cell)
	var source: Workplace = _source(world, cell, world.inventory.type_by_id(&"food"))
	test.expect(source.terrain_yield_multiplier == 1.5 and map.ground_at(cell).id == &"fertile", "berries planted on a road still use the fertile ground beneath it")
	# Only authored objects are serialized; remove the production probe before round-tripping the map.
	source.demolish()
	source.free()
	var nodes: Array[Node] = []
	for building in world.registry.all(): nodes.append(building)
	map.underlays[cell] = Vector4i(6, 0, 0, 0)
	test.expect(not LevelValidator.validate_world(world, "invalid rocky road").is_empty(), "offline validation catches roads with incompatible hidden soil")
	map.underlays[cell] = Vector4i(5, 0, 0, 0)
	var layout: Dictionary = LevelLayout.capture(map, nodes)
	test.expect(layout.has("underlays") and layout.underlays.size() == 1, "saved maps encode hidden ground separately from their road surface")
	var restored: World = LevelLayout.create_world(JSON.parse_string(JSON.stringify(layout)))
	test.expect(restored != null and (restored.get_node("Map") as TerrainMap).ground_at(cell).id == &"fertile", "hidden soil survives a JSON map round trip")
	if restored != null: restored.free()
	world.build_controller.try_build(load("res://game/building/options/ground.tres"), cell)
	test.expect(map.surface_at(cell).id == &"fertile" and not map.underlays.has(cell), "demolishing a road reveals its original soil")
	layout.underlays.append(layout.underlays[0].duplicate())
	test.expect(LevelLayout.create_world(layout) == null, "map import rejects duplicate hidden-ground records")
	world.free()
	await test.get_tree().process_frame

func _physical_build(test: Node) -> void:
	var world: World = _world(test, true)
	var house: BuildOption = load("res://game/building/options/house.tres")
	var cell := Vector2i(6, 2)
	test.expect(world.build_controller.try_build(house, cell), "discounted ground accepts a physical construction order")
	var site: ConstructionSite = world.build_controller.construction.at(cell)
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	test.expect(BuildController.price_amount(site.required, wood) == 7 and BuildController.price_amount(site.required, stone) == 14, "couriers receive the same discounted material requirements quoted in the plan")
	for frame in range(1800):
		for ant in world.population.agents(): ant._physics_process(1.0 / 30.0)
		if frame % 30 == 0: await test.get_tree().process_frame
		if world.registry.at(cell) is House: break
	test.expect(world.registry.at(cell) is House and world.inventory.quantity(wood) == 53 and world.inventory.quantity(stone) == 26, "real delivery and assembly preserve the discounted payment")
	world.free()
	await test.get_tree().process_frame

func _authoring(test: Node) -> void:
	var world: World = LevelLayout.create_world(LevelStore.load_level("builtin/five_soils"))
	test.expect(world != null and LevelValidator.validate_world(world, "five soils").is_empty(), "the bundled five-soil archipelago passes offline validation")
	if world == null: return
	var map := world.get_node("Map") as TerrainMap
	var ids := {}
	for cell in map.get_used_cells():
		var type: TerrainType = map.ground_at(cell)
		if type != null: ids[type.id] = true
	for id in [&"fertile", &"rocky", &"dry", &"wet", &"sand"]:
		test.expect(ids.has(id), "the bundled map contains each advertised terrain type")
		var texture: Texture2D = map.catalog.by_id(id).texture
		test.expect(texture.get_size() == Vector2(16, 16), "soil art remains native sixteen by sixteen pixels")
	world.free()
	world = _world(test)
	map = world.get_node("Map") as TerrainMap
	map.paint_tile(Vector2i(11, 5), Vector4i(3, 3, 0, 0), true)
	TerrainPainter.grow_wet_shore(map, Vector2i(11, 5), [])
	test.expect(map.ground_at(Vector2i(10, 4)).id == &"wet" and map.ground_at(Vector2i(12, 6)).id == &"wet", "painting water automatically creates wet neighboring ground")
	world.free()
	await test.get_tree().process_frame

func _texture_replacement(test: Node) -> void:
	var world: World = LevelLayout.DEFAULT_WORLD.instantiate()
	var map := world.get_node("Map") as TerrainMap
	var type := TerrainType.new()
	type.id = &"texture_probe"
	type.display_name = "Probe"
	type.tile = Vector4i(50, 0, 0, 0)
	type.texture = load("res://game/assets/tiles/fertile.svg")
	var catalog := TerrainCatalog.new()
	catalog.default_ground = type
	catalog.types = [type]
	map.catalog = catalog
	map.prepare_terrain()
	var source := map.tile_set.get_source(50) as TileSetAtlasSource
	test.expect(source.texture == type.texture, "the terrain resource supplies a new palette texture")
	type.texture = load("res://game/assets/tiles/dry.svg")
	test.expect(source.texture == type.texture, "replacing a terrain texture refreshes an already prepared TileSet without code or new source IDs")
	world.free()
