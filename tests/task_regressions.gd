extends RefCounted
func run(test: Node) -> void:
	var world: World = load("res://game/worlds/world_1.tscn").instantiate()
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	world.match_controller.start(world.inventory)
	var tasks: TaskDirector = world.tasks
	test.expect(tasks != null and tasks.slots.size() == 3 and tasks.closed == 0, "task mode starts with three offers")
	var seen: Dictionary[StringName, bool] = {}
	for task in tasks.slots: seen[task.id] = true
	test.expect(seen.size() == 3, "initial requests do not repeat")
	var food: ResourceType = world.inventory.type_by_id(&"food")
	var royal: ResourceType = world.inventory.type_by_id(&"royal")
	var ordinary: TileBuildOption = tasks.deck.replaced_road
	var road_cell := Vector2i(26, 25)
	var option_count: int = world.build_controller.options.size()
	var road_position: int = world.build_controller.options.find(ordinary)
	test.expect(world.build_controller.try_build(ordinary, road_cell), "ordinary road can be built before the upgrade")
	var ordinary_price: int = BuildController.price_amount(world.build_controller.price(ordinary), world.inventory.type_by_id(&"wood"))
	var before: float = world.match_controller.time_remaining
	test.expect(tasks.submit(0), "affordable request submits")
	test.expect(world.match_controller.time_remaining == before + 25 and world.inventory.quantity(royal) == 1 and tasks.closed == 1, "submission gives time rare currency and level progress once")
	var count: int = world.inventory.quantity(royal)
	before = world.match_controller.time_remaining
	test.expect(tasks.submit(0, true), "request can be skipped for its fractional fee")
	test.expect(world.match_controller.time_remaining == before and world.inventory.quantity(royal) == count, "skipping grants neither time nor rare rewards")
	# Fund a deterministic progression fixture; gameplay remains configured at its real starting stock.
	for type in world.inventory.registered_types(): world.inventory.add(type, 10000)
	for step in range(3):
		var index := 0
		while tasks.slots[index] == null: index += 1
		tasks.submit(index)
	test.expect(tasks.pending_reward and tasks.choose_reward(0), "stage completion waits for one explicit reward")
	test.expect(tasks.level == 2 and tasks.closed == 0 and world.build_controller.options.has(tasks.deck.unlocked_road), "closing the five-item pool unlocks the next level and improved road")
	var facilities: int = world.build_controller.options.filter(func(option: BuildOption) -> bool: return option is WorkplaceUpgradeOption).size()
	test.expect(not world.build_controller.options.has(ordinary) and world.build_controller.options.size() == option_count + facilities and world.build_controller.options[road_position] == tasks.deck.unlocked_road, "improved road keeps its palette slot while earned facilities occupy their own slots")
	test.expect(not world.prices.definitions.has(ordinary) and world.prices.definitions.has(tasks.deck.unlocked_road), "pricing reload tracks the active road definition")
	test.expect(BuildController.price_amount(world.build_controller.price(tasks.deck.unlocked_road), world.inventory.type_by_id(&"wood")) == ordinary_price, "replacement road preserves the one-wood base price")
	test.expect(not world.build_controller.try_build(ordinary, road_cell), "retired road option cannot be built after unlocking the replacement")
	for step in range(5):
		var index := 0
		while tasks.slots[index] == null: index += 1
		tasks.submit(index, true)
	tasks.choose_reward(1)
	test.expect(tasks.level == 3 and is_equal_approx(world.prices.global_multiplier, 0.9), "skips advance the level and apply its configured upgrade")
	var speed: float = world.population.agents()[0].speed
	for step in range(5):
		var index := 0
		while tasks.slots[index] == null: index += 1
		tasks.submit(index)
	tasks.choose_reward(2)
	test.expect(tasks.level == 4 and world.population.agents()[0].speed > speed, "repeated final-stage progression improves worker speed")
	var tile: TileBuildOption = tasks.deck.unlocked_road
	test.expect(world.build_controller.try_build(tile, Vector2i(26, 25)) and world.route_service.entry_cost(Vector2i(26, 25)) < 0.35, "replacement brush upgrades an existing road to its faster tile alternative")
	world.match_controller._process(100000)
	var stock: int = world.inventory.quantity(food)
	test.expect(not tasks.submit(0) and world.inventory.quantity(food) == stock, "expired match cannot exchange a request or revive its timer")
	world.free()
	await test.get_tree().process_frame
