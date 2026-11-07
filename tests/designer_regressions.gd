extends RefCounted
func run(test: Node) -> void:
	test_finite_sources(test)
	test_resource_facilities(test)
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
	service.events.publish(GameEvents.Kind.RESOURCE_PRODUCED, &"wood", 10)
	test.expect(service.events.count(GameEvents.Kind.RESOURCE_PRODUCED, &"wood") == 1, "one produced batch is one fact even when it contains ten units")
	test.expect(BuildController.price_amount(service.quote(option), stone) == 20, "base composite price is exact")
	service.record(GameEvents.Kind.BUILDING_BUILT, option.id)
	test.expect(BuildController.price_amount(service.quote(option), wood) == 12 and BuildController.price_amount(service.quote(option), stone) == 24, "one event increases both components by 1.2")
	var commands: Array[BuildCommand] = [BuildCommand.create(Vector2i.ZERO, option), BuildCommand.create(Vector2i.ONE, option)]
	test.expect(BuildController.price_amount(service.quote_plan(commands), wood) == 27, "batch quotes twelve then fifteen wood with upward rounding")
	test.expect(option.costs[0].amount == 10, "quotes never mutate base prices")
	option.costs[0].amount = 5
	test.expect(BuildController.price_amount(service.quote(option), wood) == 6, "editing base configuration preserves event history")
	var demolished := Building.new()
	demolished.option = option
	var discount := PriceRule.new()
	discount.event = GameEvents.Kind.BUILDING_DEMOLISHED
	discount.subject = option.id
	discount.value = 0.5
	option.price_rules = [discount]
	test.expect(BuildController.price_amount(service.quote_plan([BuildCommand.create(Vector2i.ONE, option), BuildCommand.remove(demolished)]), stone) == 10, "batch quotes include demolition-triggered price rules before construction")
	demolished.free()
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

func test_finite_sources(test: Node) -> void:
	var world: World = test.make_world()
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var workplace := Workplace.new()
	workplace.output = wood
	workplace.output_amount = 2
	workplace.work_slots = 2
	workplace.finite_supply = true
	workplace.remaining_supply = 3
	workplace.inventory = world.inventory
	var worker := Node2D.new()
	var other := Node2D.new()
	workplace.reserve_worker(worker)
	workplace.reserve_worker(other)
	var produced: Array[int] = []
	workplace.produced.connect(func(_type: ResourceType, count: int): produced.append(count))
	test.expect(workplace.complete_cycle(worker, true) and workplace.remaining_supply == 1 and workplace.pending_output_amount() == 2, "finite harvesting consumes actual output units and keeps physical cargo pending")
	workplace.take_output(1)
	test.expect(workplace.complete_cycle(other, true) and workplace.remaining_supply == 1 and produced == [2], "collecting an existing partial batch cannot consume the deposit twice")
	workplace.take_output(1)
	test.expect(workplace.complete_cycle(other, true) and workplace.remaining_supply == 0 and produced == [2, 1], "the final cycle produces only the remaining resource amount")
	workplace.take_output(10)
	test.expect(not workplace.can_run_recipe() and not workplace.complete_cycle(worker, true) and workplace.remaining_supply == 0, "an exhausted source stops producing without a negative balance")
	workplace.finite_supply = false
	test.expect(workplace.complete_cycle(worker, true) and workplace.remaining_supply == 0 and workplace.pending_output_amount() == 2, "an infinite source keeps producing without decrementing a supply counter")
	worker.free()
	other.free()
	workplace.free()
	world.free()
	var layout := {"version": LevelLayout.VERSION, "tiles": [[0, 0, 3, 0, 0, 0]], "objects": [[0, 0, "Workplace", {"finite_supply": true, "remaining_supply": 7}]]}
	world = LevelLayout.create_world(layout)
	test.expect(world != null, "map files can restore a finite resource source")
	if world != null:
		var buildings: Array[Building] = []
		world._collect_buildings(world, buildings)
		test.expect((buildings[0] as Workplace).finite_supply and (buildings[0] as Workplace).remaining_supply == 7, "a source retains its configured finite amount")
		world.free()
	layout.objects[0][3].remaining_supply = -1
	test.expect(LevelLayout.create_world(layout) == null, "map import rejects negative resource deposits")
	layout.objects[0][3].remaining_supply = 1.5
	test.expect(LevelLayout.create_world(layout) == null, "map import rejects fractional resource deposits")

func test_resource_facilities(test: Node) -> void:
	var world: World = load("res://game/worlds/world_1.tscn").instantiate()
	world.auto_start = false
	test.add_child(world)
	world.match_controller.start(world.inventory)
	var sawmill: WorkplaceUpgradeOption = load("res://game/building/options/sawmill.tres")
	var quarry: WorkplaceUpgradeOption = load("res://game/building/options/quarry.tres")
	var farm: WorkplaceUpgradeOption = load("res://game/building/options/farm.tres")
	var workplace := world.get_node("Workplace") as Workplace
	var stone := world.get_node("Workplace2") as Workplace
	var berries := world.get_node("AppleTree") as Workplace
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var slots_before: int = workplace.work_slots
	test.expect(not world.build_controller.can_build(sawmill, workplace.cell), "resource facilities start locked")
	var task := TaskSpec.new()
	task.id = &"facility_unlock_fixture"
	task.unlocks = [sawmill, quarry, farm]
	world.tasks.slots[0] = task
	test.expect(world.tasks.submit(0, true) and not world.build_controller.options.has(sawmill), "cancelling an unlocking task grants no facility")
	world.tasks.slots[0] = task
	test.expect(world.tasks.submit(0) and world.build_controller.options.has(sawmill) and world.prices.definitions.has(quarry), "completing a task unlocks its configured construction options and prices")
	test.expect(not world.build_controller.can_build(sawmill, stone.cell) and not world.build_controller.can_build(quarry, berries.cell) and not world.build_controller.can_build(farm, workplace.cell), "each facility requires the matching raw resource")
	test.expect(not world.build_controller.can_build(sawmill, Vector2i(26, 25)), "resource facilities cannot be built on empty ground")
	workplace.finite_supply = true
	workplace.remaining_supply = 5
	workplace._produce(wood, 2, true)
	var worker: AntAgent = world.population.agents()[0]
	workplace.reserve_worker(worker)
	var before: int = world.inventory.quantity(wood)
	var draft := BuildDraft.new()
	draft.controller = world.build_controller
	test.expect(draft.paint(sawmill, workplace.cell) and draft.commit(), "a facility can be planned and built on an occupied resource cell")
	test.expect(world.registry.at(workplace.cell) == workplace and workplace.work_slots == slots_before + 2 and workplace.has_worker(worker), "installing a facility adds two slots without replacing the source or evicting its worker")
	test.expect(workplace.remaining_supply == 3 and workplace.pending_output_amount() == 2 and world.inventory.quantity(wood) == before - 10, "installing a facility preserves supply and pending cargo and charges its price once")
	test.expect(not world.build_controller.try_build(sawmill, workplace.cell) and world.inventory.quantity(wood) == before - 10, "a second facility cannot stack on the same resource cell")
	test.expect((workplace.get_node("Sprite") as Sprite2D).texture == sawmill.icon and sawmill.icon.get_size() == Vector2(16, 16), "a sawmill uses its own sixteen-pixel sprite")
	sawmill.added_slots = 3
	test.expect(world.build_controller.demolish_at(workplace.cell) and world.registry.at(workplace.cell) == workplace and workplace.improvement == null and workplace.work_slots == slots_before, "demolition removes the facility while preserving the source")
	sawmill.added_slots = 2
	test.expect(workplace.remaining_supply == 3 and workplace.pending_output_amount() == 2, "demolishing a facility cannot replenish the deposit or destroy waiting goods")
	test.expect(world.build_controller.try_build(sawmill, workplace.cell) and draft.demolish(workplace.cell) and draft.commit() and workplace.improvement == null, "planned demolition also removes only the facility layer")
	workplace.remaining_supply = 0
	test.expect(not world.build_controller.try_build(sawmill, workplace.cell), "an exhausted source cannot receive a new facility")
	test.expect(world.build_controller.try_build(quarry, stone.cell) and world.build_controller.try_build(farm, berries.cell), "quarries and farms build on stone and food sources")
	world.free()
	var layout := {"version": LevelLayout.VERSION, "tiles": [[0, 0, 3, 0, 0, 0]], "objects": [[0, 0, "Workplace", {"finite_supply": true, "remaining_supply": 0, "improvement": "sawmill"}]]}
	world = LevelLayout.create_world(layout)
	test.expect(world != null, "saved maps accept an existing facility on an exhausted deposit")
	if world != null:
		world.auto_start = false
		test.add_child(world)
		var restored := world.registry.at(Vector2i.ZERO) as Workplace
		test.expect(restored.improvement == sawmill and restored.remaining_supply == 0 and not restored.can_run_recipe(), "loading a facility preserves exhaustion without regenerating resources")
		world.free()
	test.expect(LevelValidator.validate("res://game/worlds/world_1.tscn").is_empty(), "authored production level passes offline validation")
	var invalid: World = load("res://game/worlds/world_1.tscn").instantiate()
	invalid.get_node("Workplace").work_slots = 0
	var map: TileMapLayer = invalid.get_node("Map")
	map.set_cell(Vector2i(28, 26), 3, Vector2i(3, 0))
	var packed := PackedScene.new()
	packed.pack(invalid)
	var path := "user://designer-invalid-level.tscn"
	ResourceSaver.save(packed, path)
	var issues: Array[String] = LevelValidator.validate(path)
	test.expect(not issues.is_empty() and str(issues).contains("Workplace") and str(issues).contains("no accessible entry"), "validator reports bad slots and inaccessible entrances with level paths")
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
