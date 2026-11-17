extends RefCounted
## Composite prices must preserve stock, meal claims, and placement transactions.

func run(test: Node) -> void:
	await _composite_price(test)
	await _draft_and_commit(test)
	await _invalid_batches(test)
	await _construction_egress(test)
	await _layered_plan(test)
	await _planned_demolition(test)

func _composite_price(test: Node) -> void:
	var world: World = test.make_world()
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var food: ResourceType = world.inventory.type_by_id(&"food")
	var nest: SceneBuildOption = load("res://game/building/options/barracks.tres").duplicate(true)
	nest.costs = [test.entry(stone, 5), test.entry(food, 21)]
	world.build_controller.unlock_option(nest)
	var cell := Vector2i(30, 29)
	var stone_before: int = world.inventory.quantity(stone)
	test.expect(not world.build_controller.try_build(nest, cell), "composite nest cannot spend more berries than exist")
	test.expect(world.inventory.quantity(stone) == stone_before and world.registry.at(cell) == null, "failed composite nest leaves stone and map unchanged")
	nest.costs[1].amount = 20
	test.expect(world.build_controller.check(nest, cell).allowed(), "nest can spend berries reserved for meals")
	var notifications: Array[int] = [0]
	var complete: Array[bool] = []
	world.inventory.changed.connect(func():
		notifications[0] += 1
		complete.append(world.registry.at(cell) is House and world.population.count() == 10))
	test.expect(world.build_controller.try_build(nest, cell), "nest accepts the configurable five-stone twenty-food price")
	test.expect(world.inventory.quantity(stone) == stone_before - 5 and world.inventory.quantity(food) == 0, "composite nest charges every price component exactly once")
	test.expect(world.inventory.available(food) == -5 and world.population.count() == 10, "paid nest preserves the starting residents' five meal claims as a deficit")
	test.expect(notifications[0] == 1 and complete == [true], "composite build sends one complete stock and world update")
	var display := RichTextLabel.new()
	BuildCostText.show_price(display, nest.costs)
	var rendered := display.get_parsed_text()
	test.expect(rendered.contains("5") and rendered.contains("20") and not rendered.contains("+"), "symbolic construction price displays both quantities")
	display.free()
	world.free()
	await test.get_tree().process_frame

func _draft_and_commit(test: Node) -> void:
	var world: World = test.make_world()
	var road: BuildOption = load("res://game/building/options/road.tres")
	var berry: BuildOption = load("res://game/building/options/berry_bush.tres")
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
	test.expect(draft.size() == 2 and draft.costs().size() == 2, "terrain and structure retain independent options and prices")
	draft.undo()
	test.expect(draft.commands()[0].option == road, "undo restores the previous option on a repainted cell")
	draft.clear()
	test.expect(draft.size() == 0 and not draft.can_undo() and world.route_service.revision == revision, "cancel clears draft history without touching the world")
	draft.begin_stroke()
	for x in range(24, 30): draft.paint(road, Vector2i(x, 29))
	draft.end_stroke()
	draft.begin_stroke()
	draft.paint(berry, Vector2i(30, 29))
	draft.end_stroke()
	var food: ResourceType = world.inventory.type_by_id(&"food")
	world.inventory.add(food, BuildController.price_amount(draft.costs(), food))
	var wood_due := BuildController.price_amount(draft.costs(), wood)
	var updates: Array[int] = [0]
	var notifications: Array[int] = [0]
	world.route_service.navigation_changed.connect(func(): updates[0] += 1)
	world.inventory.changed.connect(func(): notifications[0] += 1)
	test.expect(draft.commit(), "valid multi-option draft commits")
	test.expect(updates[0] == 1 and world.route_service.revision == revision + 1 and world.route_service.last_changed.size() == 6, "road stroke updates navigation once with the complete changed footprint")
	test.expect(notifications[0] == 1 and world.inventory.quantity(wood) == 60 - wood_due and world.registry.at(Vector2i(30, 29)) is Workplace, "batch charges once and creates its workplace")
	test.expect(draft.size() == 0 and not draft.can_undo(), "successful commit retires the draft")
	world.free()
	await test.get_tree().process_frame

func _invalid_batches(test: Node) -> void:
	var world: World = test.make_world()
	var road: TileBuildOption = load("res://game/building/options/road.tres")
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var expensive: TileBuildOption = road.duplicate(true)
	expensive.costs = [test.entry(wood, 40)]
	world.build_controller.unlock_option(expensive)
	var commands: Dictionary[Vector2i, BuildOption] = {Vector2i(25, 29): expensive, Vector2i(26, 29): expensive}
	var revision: int = world.route_service.revision
	var map: TileMapLayer = world.get_node("Map")
	test.expect(not world.build_controller.try_build_batch(commands) and world.build_controller.last_result.code == PlacementCheck.Code.RESOURCES, "batch validates the total price rather than each affordable item")
	test.expect(world.inventory.quantity(wood) == 60 and map.get_cell_atlas_coords(Vector2i(25, 29)) == Vector2i(1, 0), "unaffordable batch leaves every cell and resource untouched")
	commands = {Vector2i(25, 29): road, Vector2i(26, 29): null}
	test.expect(not world.build_controller.try_build_batch(commands) and world.route_service.revision == revision, "invalid final command cannot partly apply earlier commands")
	var wall: TileBuildOption = road.duplicate(true)
	wall.atlas_coords = Vector2i(3, 0)
	world.build_controller.unlock_option(wall)
	commands.clear()
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		commands[Vector2i(28, 26) + offset] = wall
	test.expect(not world.build_controller.try_build_batch(commands) and world.build_controller.last_result.code == PlacementCheck.Code.NO_ESCAPE, "combined terrain changes cannot cut every safe route to food")
	test.expect(world.route_service.revision == revision and world.inventory.quantity(wood) == 60 and world.population.count() == 5, "unsafe batch leaves navigation stock and ants unchanged")
	world.free()
	await test.get_tree().process_frame

func _construction_egress(test: Node) -> void:
	var world: World = test.make_world()
	var controller := world.build_controller
	var statue: SceneBuildOption = load("res://game/building/options/queen_statue.tres")
	var feast: SceneBuildOption = load("res://game/building/options/feast.tres")
	var single_entry := statue.duplicate() as SceneBuildOption
	single_entry.entry_offsets = [Vector2i.DOWN]
	for option in [statue, feast, single_entry]:
		controller.unlock_option(option)
	var cell := Vector2i(30, 29)
	var below := cell + Vector2i.DOWN
	var stock := world.inventory.quantity(world.inventory.type_by_id(&"wood"))
	var plan: Dictionary[Vector2i, BuildOption] = {cell: single_entry, below: feast}
	test.expect(not controller.try_build_batch(plan) and controller.last_result.code == PlacementCheck.Code.NO_ENTRANCE,
		"covering a building's only entrance has its own diagnosis")
	test.expect(world.inventory.quantity(world.inventory.type_by_id(&"wood")) == stock, "failed entrance check leaves stock unchanged")
	var ant: AntAgent = world.population.agents()[0]
	ant.global_position = world.route_service.cell_to_world(cell)
	test.expect(is_finite(world.route_service.food_field().cost(cell)), "the ant starts with access to food")
	plan[cell] = statue
	test.expect(controller.try_build_batch(plan), "adjacent task buildings can use alternate entrances even with an ant inside the footprint")
	var exit := world.route_service.world_to_cell(ant.global_position)
	test.expect(exit != cell and exit != below and world.route_service.walkable(exit), "an ant is moved to a clear cell when the footprint closes")
	test.expect(is_finite(world.route_service.food_field().cost(exit)), "the relocated ant keeps its route to food")
	world.free()
	await test.get_tree().process_frame
	world = load("res://game/worlds/starter_island.tscn").instantiate()
	world.auto_start = false
	world.task_deck = null
	test.add_child(world)
	controller = world.build_controller
	controller.unlock_option(statue)
	ant = world.population.agents()[0]
	ant.global_position = world.route_service.cell_to_world(cell)
	test.expect(controller.try_build(statue, cell), "an ant on the footprint does not prevent queuing a construction site")
	var site := controller.construction.at(cell)
	test.expect(site != null and world.route_service.world_to_cell(ant.global_position) == cell, "the ant stays put while the site is only a reservation")
	if site != null:
		test.expect(controller.finish_construction(site), "the blocking site can finish while the ant is still on the cell")
		exit = world.route_service.world_to_cell(ant.global_position)
		test.expect(exit != cell and world.route_service.walkable(exit), "assembly moves the ant only when the cell actually closes")
	world.free()
	await test.get_tree().process_frame

func _layered_plan(test: Node) -> void:
	var world: World = test.make_world()
	var road: BuildOption = load("res://game/building/options/road.tres")
	var nest: BuildOption = load("res://game/building/options/barracks.tres")
	var draft := BuildDraft.new()
	draft.controller = world.build_controller
	var cell := Vector2i(30, 29)
	draft.begin_stroke()
	test.expect(draft.paint(road, cell) and draft.paint(nest, cell), "road and nest can be planned on one cell")
	draft.end_stroke()
	test.expect(draft.size() == 2, "layered plan retains both commands")
	draft.begin_stroke()
	test.expect(draft.remove_last(cell) and draft.commands()[0].option == road, "right removal peels only the latest structure")
	draft.end_stroke()
	draft.undo()
	test.expect(draft.size() == 2, "undo restores a peeled layer")
	draft.clear()
	draft.paint(nest, cell)
	draft.paint(road, cell)
	test.expect(draft.remove_last(cell) and draft.commands()[0].option == nest, "layer removal follows insertion order even when terrain was added last")
	draft.paint(road, cell)
	draft.paint(road, cell)
	test.expect(draft.size() == 2, "repeated painting does not duplicate a layer or its cost")
	var wood := world.inventory.type_by_id(&"wood")
	var stone := world.inventory.type_by_id(&"stone")
	var wood_before := world.inventory.quantity(wood)
	var stone_before := world.inventory.quantity(stone)
	var cost := draft.costs()
	test.expect(draft.commit(), "layered plan commits regardless of painting order")
	test.expect(world.registry.at(cell) is House and world.build_controller.map.get_cell_atlas_coords(cell) == Vector2i(2, 0), "committed road remains underneath its nest")
	test.expect(world.population.count() == 10
		and world.inventory.quantity(wood) == wood_before - BuildController.price_amount(cost, wood)
		and world.inventory.quantity(stone) == stone_before - BuildController.price_amount(cost, stone),
		"layered commit charges both resources and spawns once")
	world.free()
	await test.get_tree().process_frame

func _planned_demolition(test: Node) -> void:
	var world: World = test.make_world()
	var controller: BuildController = world.build_controller
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var road: BuildOption = load("res://game/building/options/road.tres")
	var berry: BuildOption = load("res://game/building/options/berry_bush.tres")
	var cell := Vector2i(30, 29)
	var food := world.inventory.type_by_id(&"food")
	world.inventory.add(food, BuildController.price_amount(controller.price(berry, cell), food) * 2)
	test.expect(controller.try_build_plan([BuildCommand.create(cell, road), BuildCommand.create(cell, berry)]), "demolition fixture has a road beneath a workplace")
	var target: Building = world.registry.at(cell)
	var revision: int = world.route_service.revision
	var stock: int = world.inventory.quantity(wood)
	var draft := BuildDraft.new()
	draft.controller = controller
	draft.begin_stroke()
	test.expect(draft.demolish(cell) and draft.demolish(cell) and draft.size() == 1, "demolition brush reserves one removal despite repeated visits")
	draft.end_stroke()
	test.expect(world.registry.at(cell) == target and world.route_service.revision == revision, "demolition preview leaves the building and navigation untouched")
	draft.begin_stroke()
	test.expect(draft.remove_last(cell) and draft.size() == 0, "right click cancels a demolition mark")
	draft.end_stroke()
	draft.undo()
	test.expect(draft.removals() == [target], "stroke undo restores a cancelled removal")
	draft.clear()
	test.expect(world.registry.at(cell) == target and world.inventory.quantity(wood) == stock, "cancelling demolition preserves the world and stock")
	draft.demolish(cell)
	test.expect(draft.paint(berry, cell), "plan can replace a building scheduled for removal")
	test.expect(draft.commit() and not is_instance_valid(target) and world.registry.at(cell) is Workplace, "demolition and replacement commit together")
	test.expect(controller.map.get_cell_atlas_coords(cell) == Vector2i(2, 0), "building demolition preserves the terrain layer")
	draft.demolish(cell)
	test.expect(draft.commit(), "standalone planned demolition commits")
	test.expect(world.registry.at(cell) == null and world.inventory.quantity(wood) == stock, "demolition has no implicit refund")
	draft.demolish(cell)
	test.expect(draft.commit() and controller.map.get_cell_atlas_coords(cell) == Vector2i(1, 0), "demolition brush restores road terrain to soil after the building is gone")
	var canteen: Canteen = world.registry.canteens()[0]
	test.expect(not draft.demolish(canteen.cell) and draft.last_result.code == PlacementCheck.Code.NO_ESCAPE, "draft cannot mark the final feeding point for demolition")
	test.expect(not controller.try_build_plan([BuildCommand.remove(canteen)]) and is_instance_valid(canteen), "controller also rejects an unsafe direct removal plan")
	var workplace: Workplace = world.registry.workplaces()[0]
	var expensive: TileBuildOption = road.duplicate(true)
	expensive.costs = [test.entry(wood, 10000)]
	controller.unlock_option(expensive)
	test.expect(not controller.try_build_plan([BuildCommand.remove(workplace), BuildCommand.create(cell, expensive)]) and is_instance_valid(workplace), "unaffordable plan cannot partially demolish an existing building")
	world.free()
	await test.get_tree().process_frame
