extends RefCounted
## Composite prices must preserve stock, meal claims, and placement transactions.

func run(test: Node) -> void:
	await _composite_price(test)
	await _draft_and_commit(test)
	await _invalid_batches(test)

func _composite_price(test: Node) -> void:
	var world: World = test.make_world()
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var food: ResourceType = world.inventory.type_by_id(&"food")
	var nest: SceneBuildOption = load("res://game/building/options/house.tres").duplicate(true)
	nest.costs = [test.entry(stone, 5), test.entry(food, 20)]
	world.build_controller.options.append(nest)
	var cell := Vector2i(30, 29)
	var stone_before: int = world.inventory.quantity(stone)
	test.expect(not world.build_controller.try_build(nest, cell), "composite nest cannot spend the starting ants' reserved meals")
	test.expect(world.inventory.quantity(stone) == stone_before and world.registry.at(cell) == null, "failed composite nest leaves stone and map unchanged")
	world.inventory.add(food, 5)
	test.expect(world.build_controller.check(nest, cell).code == PlacementCheck.Code.SPAWN_FOOD, "nest price must leave enough meals for its new residents")
	world.inventory.add(food, 5)
	var notifications: Array[int] = [0]
	var complete: Array[bool] = []
	world.inventory.changed.connect(func():
		notifications[0] += 1
		complete.append(world.registry.at(cell) is House and world.population.count() == 10))
	test.expect(world.build_controller.try_build(nest, cell), "nest accepts the configurable five-stone twenty-food price")
	test.expect(world.inventory.quantity(stone) == stone_before - 5 and world.inventory.quantity(food) == 10, "composite nest charges every price component exactly once")
	test.expect(world.inventory.available(food) == 0 and world.population.count() == 10, "paid nest retains every resident's meal reservation")
	test.expect(notifications[0] == 1 and complete == [true], "composite build sends one complete stock and world update")
	test.expect(BuildCostText.format(nest.costs) == "5 Камень + 20 Пища", "construction price text identifies both resource types")
	world.free()
	await test.get_tree().process_frame

func _draft_and_commit(test: Node) -> void:
	var world: World = test.make_world()
	var road: BuildOption = load("res://game/building/options/road.tres")
	var berry: BuildOption = load("res://game/building/options/apple_tree.tres")
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var draft := BuildDraft.new()
	draft.controller = world.build_controller
	var revision: int = world.route_service.revision
	var searches: int = world.route_service.search_count
	var map: TileMapLayer = world.get_node("Map")
	draft.begin_stroke()
	for x in range(24, 30):
		test.expect(draft.paint(road, Vector2i(x, 29)), "draft accepts road cells")
	draft.end_stroke()
	test.expect(draft.size() == 6 and world.inventory.quantity(wood) == 60, "painting records six placements without charging stock")
	test.expect(world.route_service.revision == revision and world.route_service.search_count == searches and map.get_cell_atlas_coords(Vector2i(25, 29)) == Vector2i(1, 0), "painting leaves terrain and navigation untouched")
	draft.begin_stroke()
	draft.paint(road, Vector2i(25, 29))
	draft.end_stroke()
	draft.undo()
	test.expect(draft.size() == 0, "undo removes an entire stroke and repeated visits add no history")
	draft.begin_stroke()
	draft.paint(road, Vector2i(25, 29))
	draft.end_stroke()
	draft.begin_stroke()
	draft.paint(berry, Vector2i(25, 29))
	draft.end_stroke()
	test.expect(draft.size() == 1 and draft.costs().size() == 1 and draft.costs()[0].type.id == &"food", "repainting a draft cell replaces its option and price")
	draft.undo()
	test.expect(draft.commands()[Vector2i(25, 29)] == road, "undo restores the previous option on a repainted cell")
	draft.clear()
	test.expect(draft.size() == 0 and not draft.can_undo() and world.route_service.revision == revision, "cancel clears draft history without touching the world")
	draft.begin_stroke()
	for x in range(24, 30): draft.paint(road, Vector2i(x, 29))
	draft.end_stroke()
	draft.begin_stroke()
	draft.paint(berry, Vector2i(30, 29))
	draft.end_stroke()
	var updates: Array[int] = [0]
	var notifications: Array[int] = [0]
	world.route_service.navigation_changed.connect(func(): updates[0] += 1)
	world.inventory.changed.connect(func(): notifications[0] += 1)
	test.expect(draft.commit(), "valid multi-option draft commits")
	test.expect(updates[0] == 1 and world.route_service.revision == revision + 1 and world.route_service.last_changed.size() == 6, "road stroke updates navigation once with the complete changed footprint")
	test.expect(notifications[0] == 1 and world.inventory.quantity(wood) == 54 and world.registry.at(Vector2i(30, 29)) is Workplace, "batch charges once and creates its workplace")
	test.expect(draft.size() == 0 and not draft.can_undo(), "successful commit retires the draft")
	world.free()
	await test.get_tree().process_frame

func _invalid_batches(test: Node) -> void:
	var world: World = test.make_world()
	var road: TileBuildOption = load("res://game/building/options/road.tres")
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var expensive: TileBuildOption = road.duplicate(true)
	expensive.costs = [test.entry(wood, 40)]
	world.build_controller.options.append(expensive)
	var commands: Dictionary[Vector2i, BuildOption] = {Vector2i(25, 29): expensive, Vector2i(26, 29): expensive}
	var revision: int = world.route_service.revision
	var map: TileMapLayer = world.get_node("Map")
	test.expect(not world.build_controller.try_build_batch(commands) and world.build_controller.last_result.code == PlacementCheck.Code.RESOURCES, "batch validates the total price rather than each affordable item")
	test.expect(world.inventory.quantity(wood) == 60 and map.get_cell_atlas_coords(Vector2i(25, 29)) == Vector2i(1, 0), "unaffordable batch leaves every cell and resource untouched")
	commands = {Vector2i(25, 29): road, Vector2i(26, 29): null}
	test.expect(not world.build_controller.try_build_batch(commands) and world.route_service.revision == revision, "invalid final command cannot partly apply earlier commands")
	var wall: TileBuildOption = road.duplicate(true)
	wall.atlas_coords = Vector2i(3, 0)
	world.build_controller.options.append(wall)
	commands.clear()
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		commands[Vector2i(28, 26) + offset] = wall
	test.expect(not world.build_controller.try_build_batch(commands) and world.build_controller.last_result.code == PlacementCheck.Code.NO_ESCAPE, "combined terrain changes cannot cut every safe route to food")
	test.expect(world.route_service.revision == revision and world.inventory.quantity(wood) == 60 and world.population.count() == 5, "unsafe batch leaves navigation stock and ants unchanged")
	world.free()
	await test.get_tree().process_frame
