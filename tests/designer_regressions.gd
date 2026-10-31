extends RefCounted
func run(test: Node) -> void:
	var world: World = test.make_world()
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var option := SceneBuildOption.new()
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
	test.expect(LevelValidator.validate("res://game/worlds/wolrd_1.tscn").is_empty(), "authored production level passes offline validation")
	var invalid: World = load("res://game/worlds/wolrd_1.tscn").instantiate()
	invalid.get_node("Workplace").work_slots = 0
	var map: TileMapLayer = invalid.get_node("Map")
	map.set_cell(Vector2i(28, 26), 3, Vector2i(3, 0))
	var packed := PackedScene.new()
	packed.pack(invalid)
	var path := "user://designer-invalid-level.tscn"
	ResourceSaver.save(packed, path)
	var issues: Array[String] = LevelValidator.validate(path)
	test.expect(not issues.is_empty() and str(issues).contains("Workplace") and str(issues).contains("food"), "validator reports bad slots and unreachable food with level paths")
	invalid.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await test.get_tree().process_frame
	var retry_world: World = test.make_world()
	var ant: AntAgent = retry_world.population.agents()[0]
	ant._decide()
	var job: Workplace = ant.current_workplace
	var blocked := WorkRecipe.new()
	blocked.inputs = [test.entry(retry_world.inventory.type_by_id(&"wood"), 10000)]
	blocked.outputs = [test.entry(retry_world.inventory.type_by_id(&"wood"), 1)]
	job.recipe = blocked
	ant._set_status(AntAgent.Status.WORKING)
	ant._timer = 0.0
	ant._physics_process(1.0 / 60.0)
	test.expect(ant.current_workplace == null and not ant._carrying and not job.has_worker(ant), "ingredient contention releases the slot and never traps an ant in unsafe repeat cycles")
	for place in retry_world.registry.workplaces(): place.recipe = blocked
	ant.global_position = ant.home.global_position
	ant._set_status(AntAgent.Status.HOME)
	ant._decide()
	test.expect(ant.waiting_reason == WorkPlan.WaitReason.MISSING_INPUTS, "lack of recipe ingredients has a specific home waiting reason")
	retry_world.free()
	await test.get_tree().process_frame
