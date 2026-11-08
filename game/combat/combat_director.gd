class_name CombatDirector
extends Node2D
## World-local combat owns threats, damage, defenses and traps; it never changes production policy.
signal changed
var world: World
var rules: WaveRules
var spawner := WaveSpawner.new()
var spiders: Array[SpiderAgent] = []
var traps: Dictionary[Vector2i, SpiderTrap] = {}
var _health: Dictionary[Building, int] = {}
var _fields: Dictionary[Building, NavigationField] = {}
var _revision := -1
var _time := 0.0
var _bolts: Array[Dictionary] = []

func configure(colony: World, definition: WaveRules) -> void:
	world = colony
	rules = definition
	spawner.director = self
	spawner.remaining = rules.first_wave_seconds
	world.registry.added.connect(_register)
	world.registry.removed.connect(_unregister)
	world.population.spawned.connect(_configure_ant)
	world.population.allow_warriors = true
	for building in world.registry.all(): _register(building)
	for ant in world.population.agents(): _configure_ant(ant)

func running() -> bool:
	return not get_tree().paused and world.ready_for_play and world.match_controller != null and world.match_controller.is_active()

func _configure_ant(ant: AntAgent) -> void:
	ant.combat = AntCombat.new()
	ant.combat.ant = ant
	ant.combat.director = self
	if ant.profile == null:
		ant.max_health = rules.warrior_health if ant.role == AntAgent.Role.WARRIOR else 1
		ant.health = ant.max_health
		ant.attack_damage = rules.attack_damage
	ant.cell_changed.connect(func(_old: Vector2i, next: Vector2i):
		if traps.has(next): traps[next].trigger(ant))

func _register(building: Building) -> void:
	_health[building] = maximum_health(building)

func _unregister(building: Building) -> void:
	_health.erase(building)
	_fields.erase(building)

func maximum_health(building: Building) -> int:
	if building is DefenseBuilding: return rules.wall_health if building.kind == DefenseBuilding.Kind.WALL else rules.tower_health
	return rules.nest_health if building is House else rules.building_health

func health(building: Building) -> int:
	return _health.get(building, 0)

func spawn_spider(cell: Vector2i) -> SpiderAgent:
	if not world.route_service.walkable(cell): return null
	var spider := SpiderAgent.new()
	spider.director = self
	spider.position = to_local(world.route_service.cell_to_world(cell))
	spiders.append(spider)
	add_child(spider)
	changed.emit()
	return spider

func remove_spider(spider: SpiderAgent) -> void:
	spiders.erase(spider)
	changed.emit()

func alive(target) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion(): return false
	if target is AntAgent: return target.status != AntAgent.Status.DEAD
	if target is SpiderAgent: return target.health > 0
	return target is Building and _health.has(target)

func can_melee(from: Vector2, target: Node2D) -> bool:
	if not alive(target): return false
	var navigation: RouteService = world.route_service
	var origin: Vector2i = navigation.world_to_cell(from)
	var cell: Vector2i = navigation.world_to_cell(target.global_position)
	return absi(origin.x - cell.x) + absi(origin.y - cell.y) <= 1 and from.distance_to(target.global_position) <= navigation.cell_size() * 1.15

func approach(target: Node2D, from: Vector2i) -> Route:
	if not alive(target): return Route.invalid()
	if target is Building:
		if _revision != world.route_service.revision:
			_fields.clear()
			_revision = world.route_service.revision
		var building := target as Building
		if not _fields.has(building): _fields[building] = world.route_service.reverse_field(building.entry_cells())
		return world.route_service.make_route(_fields[building].path(from))
	return world.route_service.request_route(from, world.route_service.world_to_cell(target.global_position))

func prey(cell: Vector2i) -> Node2D:
	var target: Node2D
	var best := INF
	var point: Vector2 = world.route_service.cell_to_world(cell)
	for ant in world.population.agents():
		var distance: float = point.distance_to(ant.global_position) / world.route_service.cell_size()
		if distance > rules.detection_cells: continue
		var route: Route = approach(ant, cell)
		if not route.is_valid(): continue
		var score: float = route.cost * (0.5 if ant.role == AntAgent.Role.WARRIOR else 1.0)
		if score < best:
			best = score
			target = ant
	if target != null: return target
	for building in world.registry.all():
		if building is Workplace and building.finite_supply and building.remaining_supply <= 0 and building.improvement == null: continue
		var route: Route = approach(building, cell)
		if route.is_valid() and route.cost < best:
			best = route.cost
			target = building
	return target

func nearest_spider(point: Vector2, cells: float) -> SpiderAgent:
	var best: SpiderAgent
	var distance: float = cells * world.route_service.cell_size()
	for spider in spiders:
		var value: float = point.distance_to(spider.global_position)
		if spider.health > 0 and value <= distance:
			distance = value
			best = spider
	return best

func damage(target: Node2D, amount: int) -> void:
	if amount <= 0 or not alive(target): return
	if target is AntAgent:
		target.take_damage(amount, AntAgent.DeathCause.ENEMY)
	elif target is SpiderAgent:
		target.take_damage(amount)
	elif target is Building:
		var building := target as Building
		_health[building] -= amount
		if _health[building] <= 0: _destroy(building)
	queue_redraw()
	changed.emit()

func _destroy(building: Building) -> void:
	var cells: Array[Vector2i] = building.footprint()
	if building is ConstructionSite:
		world.build_controller._remove_site(building)
	else:
		if building is House: world.inventory.destroy_nest(building, world.logistics.main_nest)
		var subject: StringName = building.improvement.id if building is Workplace and building.improvement != null else (building.option.id if building.option != null else &"initial")
		building.demolish()
		world.prices.record(GameEvents.Kind.BUILDING_DEMOLISHED, subject)
		building.queue_free()
	world.route_service.update_cells(cells, world.registry.blocked_cells())
	world.build_controller.changed.emit()
	if not world.registry.all().any(func(item: Building) -> bool: return item is House): world.match_controller.lose_colony()

func place_trap(cell: Vector2i) -> SpiderTrap:
	if traps.has(cell) or not world.route_service.walkable(cell) or world.route_service.entry_cost(cell) >= 0.5: return null
	var trap := SpiderTrap.new()
	trap.cell = cell
	trap.director = self
	trap.position = to_local(world.route_service.cell_to_world(cell))
	traps[cell] = trap
	add_child(trap)
	for ant in world.population.agents():
		if world.route_service.world_to_cell(ant.global_position) == cell: trap.trigger(ant)
	changed.emit()
	return trap

func clear_trap(cell: Vector2i) -> bool:
	if not traps.has(cell) or not world.inventory.try_spend_all(rules.trap_removal_costs): return false
	traps[cell].queue_free()
	traps.erase(cell)
	changed.emit()
	return true

func ruin_road(cell: Vector2i) -> bool:
	if world.route_service.entry_cost(cell) <= 0 or world.route_service.entry_cost(cell) >= 0.5 or rules.ruined_road == null: return false
	var ground: TileBuildOption = rules.ruined_road
	var map: TileMapLayer = world.get_node("Map")
	world.build_controller.apply_surface(ground, cell)
	world.route_service.update_cells([cell], world.registry.blocked_cells())
	world.events.publish(GameEvents.Kind.TERRAIN_CHANGED, ground.id)
	return true

func _physics_process(delta: float) -> void:
	if not running(): return
	spawner.tick(delta)
	for building in world.registry.all():
		if not building is DefenseBuilding or building.kind != DefenseBuilding.Kind.TOWER: continue
		building.shot_timer = maxf(0.0, building.shot_timer - delta)
		if not building.staffed() or building.shot_timer > 0: continue
		var target: SpiderAgent = nearest_spider(building.global_position, rules.tower_range_cells)
		if target != null:
			_bolts.append({"from": to_local(building.global_position), "to": to_local(target.global_position), "life": 0.12})
			damage(target, rules.attack_damage)
			building.shot_timer = rules.tower_shot_seconds
	for bolt in _bolts: bolt.life -= delta
	_bolts = _bolts.filter(func(bolt: Dictionary) -> bool: return bolt.life > 0)
	_time += delta
	if _time >= 0.25:
		_time = 0
		changed.emit()
	queue_redraw()

func _draw() -> void:
	for building in _health:
		var maximum: int = maximum_health(building)
		if _health[building] >= maximum: continue
		var point: Vector2 = to_local(building.global_position) + Vector2(-6, -10)
		draw_rect(Rect2(point, Vector2(12, 2)), Color("292a27"))
		draw_rect(Rect2(point, Vector2(12.0 * _health[building] / maximum, 2)), Color("e58b76"))
	for bolt in _bolts: draw_line(bolt.from, bolt.to, Color("e2c887"), 1)
