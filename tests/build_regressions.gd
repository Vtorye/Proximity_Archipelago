extends RefCounted
## Composite prices must preserve stock, meal claims, and placement transactions.

func run(test: Node) -> void:
	var world: World = test.make_world()
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var food: ResourceType = world.inventory.type_by_id(&"food")
	var nest: SceneBuildOption = load("res://game/building/options/house.tres").duplicate(true)
	nest.costs = [test.entry(stone, 5), test.entry(food, 20)]
	world.build_controller.options.append(nest)
	var cell := Vector2i(55, 54)
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
