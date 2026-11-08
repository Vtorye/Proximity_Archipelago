extends RefCounted
## Combat fixtures exercise actual agent execution independently of construction timing.
func _world(test: Node) -> World:
	var tiles: Array = []
	for x in range(14):
		for y in range(7): tiles.append([x, y, 3, 2 if y == 3 else 0, 0, 0])
	var world: World = LevelLayout.create_world({"version": 1, "tiles": tiles, "objects": [[0, 3, "build/base_nest"], [0, 4, "Food"], [6, 2, "Workplace"], [8, 4, "AppleTree"]]})
	world.auto_start = false
	world.ant_construction = false
	world.task_deck = null
	world.wave_rules = load("res://game/combat/default_waves.tres").duplicate(true)
	world.wave_rules.first_wave_seconds = 1000
	test.add_child(world)
	world.match_controller.task_mode = true
	world.match_controller.start(world.inventory)
	return world

func _advance(test: Node, world: World, seconds: float) -> void:
	for frame in range(roundi(seconds * 30)):
		for ant in world.population.agents(): ant._physics_process(1.0 / 30.0)
		world.combat._physics_process(1.0 / 30.0)
		for spider in world.combat.spiders.duplicate(): spider._physics_process(1.0 / 30.0)
		if frame % 30 == 0: await test.get_tree().process_frame

func run(test: Node) -> void:
	await _roles_and_fleeing(test)
	await _towers_and_meals(test)
	await _tower_before_chase(test)
	await _traps_and_destruction(test)
	await _waves_and_walls(test)
	await _autonomous_battle(test)
	await _base_promotion(test)
	await _slow_terrain_replanning(test)

func _roles_and_fleeing(test: Node) -> void:
	var world: World = _world(test)
	var home: House = world.logistics.main_nest
	var food: ResourceType = world.inventory.type_by_id(&"food")
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stock: int = world.inventory.quantity(wood)
	test.expect(world.population.allow_warriors and not world.population.can_recruit(home, AntAgent.Role.WARRIOR), "warriors require their full expensive recruitment price")
	world.inventory.add(food, 100)
	test.expect(world.population.recruit(home, AntAgent.Role.WARRIOR), "a wave-mode nest recruits a warrior")
	var warrior: AntAgent = world.population.agents().back()
	test.expect(warrior.role == AntAgent.Role.WARRIOR and warrior.health == 4 and warrior.attack_damage == 1 and world.inventory.quantity(wood) == stock - 10, "warrior configuration and multi-resource price apply exactly once")
	var workplace: Workplace = world.registry.workplaces()[0]
	test.expect(not workplace.reserve_worker(warrior) and world.planner.plan_work(warrior, home, warrior.needs, warrior.speed, warrior.work_time, warrior._meal) == null, "warriors cannot reserve or receive production work")
	var worker: AntAgent = world.population.agents()[0]
	worker.global_position = world.route_service.cell_to_world(Vector2i(5, 2))
	worker._release_work()
	workplace.reserve_worker(worker)
	workplace.begin_work(worker)
	worker.current_workplace = workplace
	worker._set_status(AntAgent.Status.WORKING)
	var spider: SpiderAgent = world.combat.spawn_spider(Vector2i(6, 2))
	worker._physics_process(0.05)
	test.expect(worker._destination == &"flee" and worker.status == AntAgent.Status.WALKING and workplace.worker_count() == 0 and spider.health == 6, "a civilian abandons work and runs away without approaching or attacking the spider")
	world.combat.damage(worker, 1)
	test.expect(worker.status == AntAgent.Status.DEAD, "one spider attack kills a one-HP worker")
	for hit in range(6): world.combat.damage(spider, 1)
	test.expect(spider.health == 0 and world.combat.spiders.is_empty(), "six one-damage attacks kill a six-HP spider exactly once")
	await _advance(test, world, 2)
	test.expect(warrior.current_workplace == null, "idle warrior execution never falls through to gathering")
	world.free()
	await test.get_tree().process_frame

func _towers_and_meals(test: Node) -> void:
	var world: World = _world(test)
	var home: House = world.logistics.main_nest
	world.inventory.add(world.inventory.type_by_id(&"food"), 100)
	world.population.recruit(home, AntAgent.Role.WARRIOR)
	var warrior: AntAgent = world.population.agents().back()
	var tower_option: SceneBuildOption = load("res://game/combat/tower.tres")
	test.expect(world.build_controller.try_build(tower_option, Vector2i(3, 3)), "tower construction uses the active wave defense catalog")
	var tower := world.registry.at(Vector2i(3, 3)) as DefenseBuilding
	var spider: SpiderAgent = world.combat.spawn_spider(Vector2i(5, 3))
	world.combat._physics_process(1)
	test.expect(spider.health == 6 and not tower.staffed(), "an empty tower cannot fire")
	warrior.global_position = tower.global_position
	warrior.combat.decide()
	warrior._arrive()
	test.expect(tower.staffed() and warrior.status == AntAgent.Status.GUARDING, "a warrior occupies one tower instead of patrolling")
	world.combat._physics_process(1)
	test.expect(spider.health == 5, "a staffed tower fires within its configured radius")
	warrior.needs.satiety = 59
	warrior._physics_process(0.05)
	test.expect(tower.gunner == null and not tower.staffed() and warrior._destination == &"combat_meal", "a hungry gunner leaves its station to eat at its own nest")
	world.combat._physics_process(1)
	test.expect(spider.health == 5, "tower remains disabled while its gunner is away")
	# No spider execution here: isolate the complete nest-food round trip.
	for frame in range(300):
		warrior._physics_process(1.0 / 30.0)
		if warrior.needs.satiety > 110: break
	test.expect(warrior.needs.satiety > 110 and warrior.global_position.distance_to(home.global_position) < 1, "warrior consumes a reserved meal at home and restores satiety")
	warrior.global_position = tower.global_position
	warrior.combat.decide()
	warrior._arrive()
	warrior.die(AntAgent.DeathCause.ENEMY)
	test.expect(not tower.staffed() and tower.gunner == null, "a killed gunner disables the tower immediately")
	world.free()
	await test.get_tree().process_frame

func _tower_before_chase(test: Node) -> void:
	var world: World = _world(test)
	world.inventory.add(world.inventory.type_by_id(&"food"), 100)
	world.population.recruit(world.logistics.main_nest, AntAgent.Role.WARRIOR)
	var warrior: AntAgent = world.population.agents().back()
	var tower_option: SceneBuildOption = load("res://game/combat/tower.tres")
	world.build_controller.try_build(tower_option, Vector2i(3, 3))
	var tower := world.registry.at(Vector2i(3, 3)) as DefenseBuilding
	world.combat.spawn_spider(Vector2i(5, 3))
	warrior.combat.physics(0.05)
	test.expect(tower.gunner == warrior and warrior._destination == &"combat_tower", "an idle warrior claims a free tower before chasing a spider that is already on the map")
	world.free()
	await test.get_tree().process_frame

func _traps_and_destruction(test: Node) -> void:
	var world: World = _world(test)
	var combat: CombatDirector = world.combat
	var cell := Vector2i(2, 3)
	var trap: SpiderTrap = combat.place_trap(cell)
	test.expect(trap != null and combat.place_trap(Vector2i(2, 2)) == null, "spiders place traps only on roads")
	var worker: AntAgent = world.population.agents()[0]
	worker.global_position = world.route_service.cell_to_world(Vector2i(1, 3))
	worker._walk(world.route_service.make_route([Vector2i(1, 3), cell]), &"wander")
	worker._physics_process(1.0)
	test.expect(worker.status == AntAgent.Status.DEAD and combat.traps.has(cell), "entering a trapped road kills the worker without resurrecting it on arrival")
	trap.trigger(world.population.agents()[0])
	test.expect(world.population.count() == 3 and combat.traps.has(cell), "the same trap kills another worker and stays on the map")
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	var stone: ResourceType = world.inventory.type_by_id(&"stone")
	var before: int = world.inventory.quantity(wood)
	test.expect(combat.clear_trap(cell) and world.inventory.quantity(wood) == before - 2 and not combat.traps.has(cell), "removing a trap pays its configured composite cost")
	test.expect(not combat.clear_trap(cell) and world.inventory.quantity(wood) == before - 2, "removed traps cannot charge twice")
	var revision: int = world.route_service.revision
	test.expect(combat.ruin_road(Vector2i(3, 3)) and is_equal_approx(world.route_service.entry_cost(Vector2i(3, 3)), 1.6) and world.route_service.revision == revision + 1, "spider sabotage destroys a road and updates navigation")
	world.inventory.try_spend_all([test.entry(wood, world.inventory.available(wood))])
	combat.place_trap(cell)
	var stone_before: int = world.inventory.quantity(stone)
	test.expect(not combat.clear_trap(cell) and combat.traps.has(cell) and world.inventory.quantity(stone) == stone_before, "unaffordable trap removal leaves the trap and all resources intact")
	var saboteur: SpiderAgent = combat.spawn_spider(Vector2i(4, 3))
	saboteur._sabotage = 0
	saboteur._physics_process(0.001)
	test.expect(combat.traps.has(Vector2i(4, 3)), "spider execution autonomously places a road trap when its sabotage cooldown expires")
	saboteur._sabotage = 0
	saboteur._physics_process(0.001)
	test.expect(is_equal_approx(world.route_service.entry_cost(Vector2i(4, 3)), 1.6), "a spider can subsequently ruin the trapped road while the trap persists")
	combat.damage(saboteur, 100)
	var berries: Workplace = world.registry.at(Vector2i(8, 4)) as Workplace
	combat.spawn_spider(Vector2i(8, 3))
	await _advance(test, world, 10)
	test.expect(not is_instance_valid(berries) or not berries.is_inside_tree(), "an autonomous spider can find and destroy a berry bush")
	world.free()
	await test.get_tree().process_frame

func _waves_and_walls(test: Node) -> void:
	var world: World = _world(test)
	var combat: CombatDirector = world.combat
	var spawn_cells: Array[Vector2i] = combat.spawner.spawn_cells()
	test.expect(not spawn_cells.is_empty() and spawn_cells.all(func(cell: Vector2i) -> bool: return world.route_service.walkable(cell) and cell.x >= 8), "wave entrances use distant reachable shore land, never water or the colony interior")
	combat.spawner.remaining = 0.05
	combat._physics_process(0.1)
	test.expect(combat.spawner.number == 1 and combat.spiders.size() == 2 and combat.spawner.remaining == 60, "the first wave spawns its configured count and schedules the next wave")
	combat.spawner.remaining = 0
	combat._physics_process(0.1)
	test.expect(combat.spawner.number == 2 and combat.spiders.size() == 5, "later waves add the configured extra spider")
	var wall_option: SceneBuildOption = load("res://game/combat/wall.tres")
	test.expect(world.build_controller.try_build(wall_option, Vector2i(3, 3)) and not world.route_service.walkable(Vector2i(3, 3)), "finished walls block civilian and spider navigation")
	var wall: Building = world.registry.at(Vector2i(3, 3))
	combat.damage(wall, combat.rules.wall_health)
	test.expect(world.registry.at(Vector2i(3, 3)) == null and world.route_service.walkable(Vector2i(3, 3)), "destroying a wall opens its cell immediately")
	# Enclose the original nest in the current navigation graph only.
	world.route_service.rebuild([Vector2i(0, 2), Vector2i(1, 3), Vector2i(0, 4)])
	spawn_cells = combat.spawner.spawn_cells()
	test.expect(not spawn_cells.is_empty() and spawn_cells.all(func(cell: Vector2i) -> bool: return cell.x >= 8), "a disconnected defensive enclosure does not move spawns inside the walls")
	var before_pause: float = combat.spawner.remaining
	test.get_tree().paused = true
	combat._physics_process(5)
	test.expect(combat.spawner.remaining == before_pause, "pausing freezes the enemy wave clock")
	test.get_tree().paused = false
	var home: House = world.logistics.main_nest
	combat.damage(home, combat.rules.nest_health)
	test.expect(world.match_controller.is_finished() and world.population.count() == 0, "destruction of the last nest kills its residents and ends the match")
	test.expect(world.inventory.quantity(world.inventory.type_by_id(&"wood")) == 0 and world.inventory.available(world.inventory.type_by_id(&"food")) >= 0, "destroyed base inventory and meal claims cannot survive as phantom resources")
	world.free()
	await test.get_tree().process_frame

func _autonomous_battle(test: Node) -> void:
	var world: World = _world(test)
	var home: House = world.logistics.main_nest
	world.inventory.add(world.inventory.type_by_id(&"food"), 100)
	world.population.recruit(home, AntAgent.Role.WARRIOR)
	world.population.recruit(home, AntAgent.Role.WARRIOR)
	var map: TileMapLayer = world.get_node("Map")
	for x in range(14): map.set_cell(Vector2i(x, 5), 3, Vector2i(1, 0))
	world.route_service.rebuild()
	var fighters: Array[AntAgent] = []
	for ant in world.population.agents():
		if ant.role == AntAgent.Role.WARRIOR:
			fighters.append(ant)
			ant.global_position = world.route_service.cell_to_world(Vector2i(9, 5))
			ant._timer = 0
	var spider: SpiderAgent = world.combat.spawn_spider(Vector2i(11, 5))
	await _advance(test, world, 15)
	test.expect(not is_instance_valid(spider) or spider.health == 0, "autonomous warriors approach and kill a spider through real movement and melee")
	test.expect(fighters.any(func(ant: AntAgent) -> bool: return is_instance_valid(ant) and ant.status != AntAgent.Status.DEAD), "two warriors can win the configured six-HP spider encounter")
	world.free()
	await test.get_tree().process_frame

func _base_promotion(test: Node) -> void:
	var world: World = _world(test)
	world.inventory.add(world.inventory.type_by_id(&"royal"), 1)
	var option: SceneBuildOption = load("res://game/building/options/base_nest.tres")
	world.build_controller.try_build(option, Vector2i(11, 3))
	var secondary: House = world.registry.at(Vector2i(11, 3)) as House
	var wood: ResourceType = world.inventory.type_by_id(&"wood")
	world.inventory.deposit(secondary, [test.entry(wood, 7)])
	var primary: House = world.logistics.main_nest
	world.combat.damage(primary, world.wave_rules.nest_health)
	test.expect(world.logistics.main_nest == secondary and not world.match_controller.is_finished() and world.inventory.quantity(wood) == 7, "a surviving base becomes primary without inheriting destroyed stock")
	test.expect(world.inventory.add(wood, 1) and world.inventory.quantity(wood) == 8 and world.inventory.main_quantity(wood) == 8, "the promoted base retains a valid ledger for new resources")
	world.free()
	await test.get_tree().process_frame

func _slow_terrain_replanning(test: Node) -> void:
	var world: World = _world(test)
	var map: TileMapLayer = world.get_node("Map")
	for cell in map.get_used_cells(): map.set_cell(cell, 3, Vector2i(1, 0))
	world.route_service.rebuild()
	var spider: SpiderAgent = world.combat.spawn_spider(Vector2i(12, 5))
	var start: Vector2i = world.route_service.world_to_cell(spider.global_position)
	await _advance(test, world, 3.0)
	test.expect((world.route_service.world_to_cell(spider.global_position) - start).abs().x + (world.route_service.world_to_cell(spider.global_position) - start).abs().y >= 2, "a spider keeps moving across slow soil while retargeting each second")
	var invalid: WaveRules = world.wave_rules.duplicate(true)
	invalid.attack_seconds = 0
	test.expect(not invalid.validate().is_empty(), "combat configs reject zero attack intervals before gameplay")
	world.free()
	await test.get_tree().process_frame
