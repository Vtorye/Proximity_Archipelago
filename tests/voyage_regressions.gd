extends RefCounted
func run(test: Node) -> void:
	var template := LevelLayout.DEFAULT_WORLD.instantiate() as World
	var first := LevelLayout.encode(IslandGenerator.generate_data(template, 8123, 0, 0, 50))
	var starter := Vector2i(int(first.objects[0][0]), int(first.objects[0][1]))
	for seed_value in [1, 52, 991]:
		var sample := LevelLayout.instantiate_world(IslandGenerator.generate_data(template, seed_value, 2, seed_value % 3, 50))
		test.expect(sample != null and LevelValidator.validate_world(sample, "seed " + str(seed_value)).is_empty(), "multiple seed and biome combinations produce playable maps")
		var grid := TileGrid.new()
		grid.setup(sample.get_node("Map"), [])
		var components := {}
		for cell in grid.walkable_cells(): components[grid.component(cell)] = true
		test.expect(components.size() >= 3, "archipelago generation retains disconnected islands")
		sample.free()
	for row in first.objects:
		if row.size() > 3:
			test.expect(row[3].finite_supply and row[3].remaining_supply > 0, "generated resource nodes have finite, positive stock")
			if row[2] != "Food":
				var offset := Vector2i(int(row[0]), int(row[1])) - starter
				test.expect(absi(offset.x) + absi(offset.y) >= 6, "generated deposits stay away from the starter nest")
	var again := LevelLayout.encode(IslandGenerator.generate_data(template, 8123, 0, 0, 50))
	test.expect(first == again and first.tiles.size() == 2500, "island generation is deterministic and respects the chosen extent")
	test.expect(first != LevelLayout.encode(IslandGenerator.generate_data(template, 8124, 0, 0, 50)), "different seeds create different maps")
	_test_generation_rules(test, template)
	template.free()
	var world: World = LevelLayout.create_world(first)
	test.expect(LevelValidator.validate_world(world, "generated").is_empty(), "generated starter colony has valid terrain, entrances and resources")
	var built_berry := load("res://game/entities/berry_bush.tscn").instantiate() as Workplace
	test.expect(built_berry.finite_supply and built_berry.remaining_supply == 100, "built berry bushes have finite stock")
	built_berry.free()
	world.auto_start = false
	world.waves.enabled = true
	world.waves.rules = load("res://game/combat/default_waves.tres")
	test.add_child(world)
	world.match_controller.start(world.inventory)
	for type in world.inventory.registered_types(): world.inventory.add(type, 10000)
	var home: House = world.logistics.main_nest
	var warrior: AntAgent = world.population._create_resident(home, AntAgent.Role.WARRIOR)
	warrior.profile = warrior.profile.duplicate()
	warrior.profile.satiety_capacity = 60
	warrior.apply_profile()
	world.population._add_resident(home, warrior)
	test.expect(warrior.needs.capacity == 60 and warrior.max_health == 4, "warrior profile sets an individual energy capacity and combat stats")
	test.expect(not warrior.combat._meal_due(), "a full 60-energy warrior does not immediately seek a meal")
	warrior.combat.decide()
	test.expect(warrior._destination == &"combat_patrol", "idle warrior patrols points of interest instead of staying home")
	warrior.needs.satiety = 29
	test.expect(warrior.combat._meal_due(), "warrior meal threshold follows its own capacity percentage")
	var custom: AntAgent = world.population._create_resident(home, AntAgent.Role.WORKER)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	custom.add_child(sprite)
	world.population._add_resident(home, custom)
	test.expect(custom.get_node_or_null("Sprite") == sprite and not sprite.is_queued_for_deletion(), "authored ant scene keeps its custom sprite instead of discarding it")
	custom.free()
	warrior.needs.eat()
	test.expect(warrior.needs.satiety == 60, "eating refills the individual capacity, not a global constant")
	var tower_option: BuildOption = load("res://game/combat/tower.tres")
	var tower_cell: Vector2i = home.cell + Vector2i(2, 2)
	world.build_controller.construction = null
	test.expect(world.build_controller.try_build(tower_option, tower_cell), "tower fixture can be placed beside the nest")
	world.build_controller.construction = world.population.construction
	warrior.combat.decide()
	test.expect(warrior.combat.tower == world.registry.at(tower_cell) and warrior._destination == &"combat_tower", "warrior reserves and approaches a free tower before patrolling")
	for level in range(4):
		for step in range(5):
			var index := 0
			while world.tasks.slots[index] == null: index += 1
			var order := world.tasks.start_order(world.tasks.slots[index].id, &"build")
			world.build_controller.order_completed.emit(order)
		test.expect(world.tasks.pending_reward and world.tasks.start_order(&"missing", &"build") == null, "completed stage waits for exactly one upgrade choice")
		test.expect(world.tasks.choose_reward(level % 3), "a valid reward advances the task ladder")
		test.expect(not world.tasks.choose_reward(0), "reward cannot be claimed twice")
	test.expect(world.tasks.level == 5 and world.build_controller.options.has(world.voyage_rules.ship), "reaching level five unlocks ship construction")
	var berry_option: BuildOption = load("res://game/building/options/berry_bush.tres")
	var site_cell := home.cell
	var best_distance := INF
	var grid := world.route_service.snapshot()
	for cell in grid.walkable_cells():
		var distance := Vector2(cell - home.cell).length_squared()
		if distance < best_distance and grid.connected(home.cell, cell) and world.build_controller.can_build(berry_option, cell):
			site_cell = cell
			best_distance = distance
	test.expect(world.build_controller.try_build(berry_option, site_cell), "a paid unfinished building exists in the save fixture")
	var site: ConstructionSite = world.build_controller.construction.at(site_cell)
	test.expect(site != null, "saved building is a real construction site")
	var carrier: AntAgent = world.population.agents().filter(func(ant: AntAgent): return ant.role == AntAgent.Role.CARRIER)[0]
	carrier.construction.decide()
	if carrier.construction.job != null: carrier.construction.job.picked_up = true
	world.combat.spawn_spider(home.cell + Vector2i(5, 2)).take_damage(1)
	world.combat.spawner.number = 3
	world.combat.spawner.remaining = 17.5
	warrior.combat._attack = 0.6
	(world.registry.at(tower_cell) as DefenseBuilding).shot_timer = 0.4
	var snapshot: Dictionary = SessionSave.capture(world)
	var path := "user://voyage-regression.save"
	test.expect(SessionSave.write(world, path) == OK and not SessionSave.read(path).is_empty(), "save file writes and reads an object-free snapshot")
	var restored: World = LevelLayout.create_world(snapshot.layout)
	restored.auto_start = false
	restored.waves.enabled = true
	restored.waves.rules = load("res://game/combat/default_waves.tres")
	test.add_child(restored)
	# Simulate an older snapshot without per-nest storage settings.
	for index in range(snapshot.layout.objects.size()):
		var row: Array = snapshot.layout.objects[index]
		if restored.registry.at(Vector2i(row[0], row[1])) is House:
			for key in ["funds_construction", "storage_capacity", "orders", "requests"]:
				snapshot.buildings[index].erase(key)
	SessionSave.apply(restored, snapshot)
	test.expect(restored.logistics.main_nest.funds_construction, "legacy snapshot keeps the authored construction funding default")
	test.expect(restored.population.count() == world.population.count() and restored.tasks.level == 5 and restored.tasks.buffs == world.tasks.buffs, "save restores residents, progression and chosen rewards")
	for type in world.inventory.registered_types():
		test.expect(restored.inventory.quantity(type) == world.inventory.quantity(type), "save preserves each colony resource total")
	test.expect(restored.build_controller.construction.sites.size() == 1 and restored.match_controller.time_remaining == world.match_controller.time_remaining, "save retains unfinished construction and remaining time")
	var restored_carrier: AntAgent = restored.population.agents().filter(func(ant: AntAgent): return ant.role == AntAgent.Role.CARRIER)[0]
	test.expect(restored_carrier.construction.has_cargo() and restored_carrier.construction.job.materials[0].amount == carrier.construction.job.materials[0].amount, "construction cargo in transit is restored exactly once")
	test.expect(restored.combat.spiders.size() == 1 and restored.combat.spiders[0].health == 5 and restored.combat.spawner.number == 3 and restored.combat.spawner.remaining == 17.5, "save restores enemy health and wave schedule")
	var restored_warrior: AntAgent = restored.population.agents().filter(func(ant: AntAgent): return ant.role == AntAgent.Role.WARRIOR)[0]
	test.expect(is_equal_approx(restored_warrior.combat._attack, 0.6) and is_equal_approx((restored.registry.at(tower_cell) as DefenseBuilding).shot_timer, 0.4), "loading does not reset warrior or tower attack cooldowns")
	test.expect(restored.voyage.seed_value == world.voyage.seed_value, "saving retains the campaign destination seed")
	test.expect(restored_warrior.needs.capacity == warrior.needs.capacity and restored_warrior.needs.satiety == warrior.needs.satiety, "save preserves personal hunger values")
	test.expect(SessionSave.write(world, path) == OK, "second save creates the previous-save backup")
	var corrupt := FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_string("bad save")
	corrupt.close()
	test.expect(not SessionSave.read(path).is_empty(), "damaged newest save falls back to the previous valid snapshot")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(path + suffix)
	# Complete the ship through the same registered-building event as physical construction.
	world.build_controller.construction = null
	var map: TerrainMap = world.get_node("Map")
	var land_cell: Vector2i = home.cell
	test.expect(world.build_controller.placement_check(world.voyage_rules.ship, land_cell).code == PlacementCheck.Code.WATER_REQUIRED, "the ship requires water")
	var ship_cell := Vector2i(-1, -1)
	var deep_water := Vector2i(-1, -1)
	for cell in map.get_used_cells():
		if map.surface_at(cell).kind != TerrainType.Kind.WATER:
			continue
		var check: PlacementCheck = world.build_controller.placement_check(world.voyage_rules.ship, cell)
		if check.code == PlacementCheck.Code.SHORE_REQUIRED:
			deep_water = cell
		elif check.allowed() and world.logistics.construction_sources(world.voyage_rules.ship.entries_at(cell)).has(home):
			ship_cell = cell
	test.expect(world.build_controller.placement_check(world.voyage_rules.ship, deep_water).code == PlacementCheck.Code.SHORE_REQUIRED, "water without a walkable shore is rejected")
	test.expect(world.build_controller.try_build(world.voyage_rules.ship, ship_cell), "unlocked ship can finish on water at the shore")
	test.expect(world.voyage.departed and world.match_controller.is_finished() and world.voyage.offers.size() == 3, "finished ship commits one victory and three destinations")
	var preview_layout: Dictionary = world.voyage.destination(1)
	var destination: Dictionary = world.voyage.travel(1)
	test.expect(preview_layout.tiles == destination.tiles and preview_layout.objects == destination.objects, "destination preview and traveled layout share the exact cells and landmarks")
	var next: World = LevelLayout.create_world(destination)
	next.auto_start = false
	test.add_child(next)
	next.voyage.apply(destination.journey)
	test.expect(next.voyage.island == 2 and next.tasks.buffs == world.tasks.buffs and next.match_controller.starting_duration() < next.match_controller.match_duration, "travel keeps buffs and increases island difficulty")
	for type in world.inventory.registered_types():
		test.expect(next.inventory.quantity(type) == world.inventory.quantity(type), "travel transfers accumulated colony stock without a starter-stock bonus")
	world.free()
	restored.free()
	next.free()
	await test.get_tree().process_frame

func _test_generation_rules(test: Node, template: World) -> void:
	var original := template.island_generation
	var custom := original.duplicate() as IslandGenerationRules
	custom.default_extent = 44
	custom.canteen_distance = 4
	custom.starter_deposits_per_resource = 1
	custom.extra_deposit_chance = 0.0
	custom.deposit_budgets = Vector3i(21, 22, 23)
	template.island_generation = custom
	var generated := IslandGenerator.generate_data(template, 8123)
	test.expect(generated != null and generated.tiles.size() == 44 * 44, "the world resource sets the default generated extent")
	if generated != null:
		var displacement := generated.objects[1].cell - generated.objects[0].cell
		test.expect(absi(displacement.x) + absi(displacement.y) == 4, "the canteen uses the authored distance from the nest")
		test.expect(generated.objects.size() == 5 and generated.objects[2].remaining_supply == 21 and generated.objects[3].remaining_supply == 22 and generated.objects[4].remaining_supply == 23, "configured deposit counts and budgets are used in the generated layout")
	test.expect(original.default_extent == 80 and original.deposit_budgets == Vector3i(900, 900, 900), "custom generation leaves the shared resource unchanged")
