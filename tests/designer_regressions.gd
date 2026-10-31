extends RefCounted
func run(test: Node) -> void:
	var world: World = test.make_world()
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var option := BuildOption.new()
	option.id = &"test_house"
	option.costs = [test.entry(wood, 10), test.entry(stone, 20)]
	var rule := PriceRule.new()
	rule.subject = option.id
	option.price_rules = [rule]
	var service := PriceService.new()
	test.expect(BuildController.price_amount(service.quote(option), stone) == 20, "base composite price is exact")
	service.record(GameEvents.Kind.BUILDING_BUILT, option.id)
	test.expect(BuildController.price_amount(service.quote(option), wood) == 12 and BuildController.price_amount(service.quote(option), stone) == 24, "one event increases both components by 1.2")
	var commands: Array[BuildCommand] = [BuildCommand.create(Vector2i.ZERO, option), BuildCommand.create(Vector2i.ONE, option)]
	test.expect(BuildController.price_amount(service.quote_plan(commands), wood) == 27, "batch quotes twelve then fifteen wood with upward rounding")
	test.expect(option.costs[0].amount == 10, "quotes never mutate base prices")
	option.costs[0].amount = 5
	test.expect(BuildController.price_amount(service.quote(option), wood) == 6, "editing base configuration preserves event history")
	var recipe := WorkRecipe.new()
	recipe.inputs = [test.entry(wood, 60), test.entry(stone, 41)]
	recipe.outputs = [test.entry(stone, 2)]
	var workplace := Workplace.new()
	workplace.recipe = recipe
	workplace.inventory = world.inventory
	var worker := Node2D.new()
	workplace.reserve_worker(worker)
	test.expect(not workplace.complete_cycle(worker) and world.inventory.quantity(wood) == 60, "missing recipe input cannot partly consume other ingredients")
	recipe.inputs[1].amount = 40
	var output: Array[int] = []
	workplace.produced.connect(func(_type: ResourceType, amount: int): output.append(amount))
	test.expect(workplace.complete_cycle(worker) and output == [2] and world.inventory.quantity(wood) == 0 and world.inventory.quantity(stone) == 0, "recipe consumes both inputs and emits its configured output")
	worker.free()
	workplace.free()
	service.free()
	world.free()
	await test.get_tree().process_frame
