extends RefCounted
func run(test: Node) -> void:
	var world: World = load("res://game/worlds/starter_island.tscn").instantiate()
	world.auto_start = false
	world.build_controller.physical_construction = false
	test.add_child(world)
	world.match_controller.start(world.inventory)
	var tasks: TaskDirector = world.tasks
	test.expect(tasks != null and tasks.slots.size() == 3 and tasks.closed == 0, "royal requests start with three offers")
	var seen: Dictionary[StringName, bool] = {}
	for task in tasks.slots: seen[task.id] = true
	test.expect(seen.size() == 3, "initial requests do not repeat")
	var ordinary: TileBuildOption = tasks.deck.replaced_road
	var road_cell := Vector2i(26, 25)
	var option_count: int = world.build_controller.options.size()
	var road_position: int = world.build_controller.options.find(ordinary)
	test.expect(world.build_controller.try_build(ordinary, road_cell), "ordinary road can be built before upgrade")
	var ordinary_price: int = BuildController.price_amount(world.build_controller.price(ordinary), world.inventory.type_by_id(&"wood"))
	var requested := tasks.start_order(tasks.slots[0].id, &"build")
	test.expect(requested != null and tasks.start_order(tasks.slots[1].id, &"build") != null, "previewing one order leaves the other offers available")
	var before: float = world.match_controller.time_remaining
	var previous_closed: int = tasks.closed
	var royal: ResourceType = world.inventory.type_by_id(&"royal")
	world.build_controller.built.emit(requested.variant.building, road_cell)
	test.expect(tasks.closed == previous_closed, "a matching regular building does not complete the order")
	world.build_controller.order_completed.emit(requested)
	test.expect(tasks.closed == previous_closed + 1 and world.match_controller.time_remaining == before + 25 and world.inventory.quantity(royal) == 1, "matching completion grants configured rewards")
	for type in world.inventory.registered_types(): world.inventory.add(type, 10000)
	while tasks.closed < tasks.stage().tasks.size():
		var index := 0
		while tasks.slots[index] == null: index += 1
		var order := tasks.start_order(tasks.slots[index].id, &"build")
		world.build_controller.order_completed.emit(order)
	test.expect(tasks.pending_reward and tasks.choose_reward(0), "stage completion waits for one explicit reward")
	test.expect(tasks.level == 2 and tasks.closed == 0 and world.build_controller.options.has(tasks.deck.unlocked_road), "closing the five-item pool unlocks the next level")
	var facilities: int = world.build_controller.options.filter(func(option: BuildOption) -> bool: return option is WorkplaceUpgradeOption).size()
	test.expect(not world.build_controller.options.has(ordinary) and world.build_controller.options.size() == option_count + facilities and world.build_controller.options[road_position] == tasks.deck.unlocked_road, "road upgrade preserves its palette slot")
	test.expect(not world.prices.tracks(ordinary) and world.prices.tracks(tasks.deck.unlocked_road), "pricing reload tracks active road")
	test.expect(BuildController.price_amount(world.build_controller.price(tasks.deck.unlocked_road), world.inventory.type_by_id(&"wood")) == ordinary_price, "replacement road preserves base price")
	test.expect(not world.build_controller.try_build(ordinary, road_cell), "retired road option cannot be built")
	while tasks.closed < tasks.stage().tasks.size():
		var index := 0
		while tasks.slots[index] == null: index += 1
		var order := tasks.start_order(tasks.slots[index].id, &"build")
		world.build_controller.order_completed.emit(order)
	tasks.choose_reward(1)
	test.expect(tasks.level == 3 and is_equal_approx(world.prices.multiplier(), 0.9), "completed orders apply level upgrade")
	var speed: float = world.population.agents()[0].speed
	while tasks.closed < tasks.stage().tasks.size():
		var index := 0
		while tasks.slots[index] == null: index += 1
		var order := tasks.start_order(tasks.slots[index].id, &"build")
		world.build_controller.order_completed.emit(order)
	tasks.choose_reward(2)
	test.expect(tasks.level == 4 and world.population.agents()[0].speed > speed, "repeated progression improves worker speed")
	var tile: TileBuildOption = tasks.deck.unlocked_road
	test.expect(world.build_controller.try_build(tile, Vector2i(26, 25)) and world.route_service.entry_cost(Vector2i(26, 25)) < 0.35, "replacement road paints faster tile")
	world.match_controller._process(100000)
	test.expect(tasks.start_order(tasks.slots[0].id, &"build") == null, "expired match cannot start an order")
	world.free()
	await test.get_tree().process_frame
