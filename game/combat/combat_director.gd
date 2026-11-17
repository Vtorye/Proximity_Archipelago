class_name CombatDirector
extends Node2D
## World-local combat owns threats, damage, defenses and traps; it never changes production policy.
signal changed
var world: World
@export var enabled := false
@export var rules: WaveRules
@export var enemy_scenes: Array[PackedScene] = []
var spawner := WaveSpawner.new()
var spiders: Array[SpiderAgent] = []
var traps: Dictionary[Vector2i, SpiderTrap] = {}
var _health: Dictionary[Building, int] = {}
var _fields: Dictionary[Building, NavigationField] = {}
var _time := 0.0
var _bolts: Array[Dictionary] = []

func validate() -> Array[String]:
	var errors: Array[String] = []
	if rules == null:
		errors.append("missing wave rules")
	else:
		errors.append_array(rules.validate())
	if enemy_scenes.is_empty():
		errors.append("missing enemy scenes")
	for scene in enemy_scenes:
		var enemy: Node = scene.instantiate() if scene != null else null
		if not enemy is SpiderAgent:
			errors.append("enemy scene must have a SpiderAgent root")
		if enemy != null:
			enemy.free()
	return errors

func configure(colony: World, definition: WaveRules) -> void:
	world = colony
	rules = definition
	spawner.director = self
	spawner.interval_seconds = rules.wave_interval_seconds
	spawner.remaining = rules.first_wave_seconds
	world.registry.added.connect(_register)
	world.registry.removed.connect(_unregister)
	world.population.spawned.connect(_configure_ant)
	world.population.allow_warriors = true
	for building in world.registry.all(): _register(building)
	for ant in world.population.agents(): _configure_ant(ant)

func configure_wave_interval_reduction(reduction: float, minimum: float) -> void:
	spawner.interval_seconds = maxf(minimum, rules.wave_interval_seconds - reduction)

func running() -> bool:
	return world != null and not get_tree().paused and world.ready_for_play and world.match_controller != null and world.match_controller.is_active()

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
	if building is Workplace and not building.colony_owned:
		building.improvement_changed.connect(_reset_improvement_health.bind(building))

func _reset_improvement_health(building: Building) -> void:
	if _health.has(building):
		_health[building] = maximum_health(building)
		changed.emit()

func _unregister(building: Building) -> void:
	if building is Workplace:
		var reset := _reset_improvement_health.bind(building)
		if building.improvement_changed.is_connected(reset):
			building.improvement_changed.disconnect(reset)
	_health.erase(building)
	_fields.erase(building)

func maximum_health(building: Building) -> int:
	if building is DefenseBuilding: return rules.wall_health if building.kind == DefenseBuilding.Kind.WALL else rules.tower_health
	return rules.nest_health if building is House else rules.building_health

func health(building: Building) -> int:
	return _health.get(building, 0)

func spawn_spider(cell: Vector2i, scene_path := "") -> SpiderAgent:
	if not world.route_service.walkable(cell): return null
	var scene: PackedScene = enemy_scenes.pick_random()
	for candidate in enemy_scenes:
		if candidate.resource_path == scene_path:
			scene = candidate
			break
	var spider := scene.instantiate() as SpiderAgent
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
		var building := target as Building
		var field: NavigationField = _fields.get(building)
		if field == null or field.revision != world.route_service.revision:
			field = world.route_service.reverse_field(building.entry_cells(), field)
			_fields[building] = field
		return world.route_service.make_route(field.path(from))
	return world.route_service.request_route(from, world.route_service.world_to_cell(target.global_position))

func is_spider_target(building: Variant) -> bool:
	if not alive(building) or not building is Building:
		return false
	if building is Workplace:
		return building.improvement != null or (building.colony_owned and (not building.finite_supply or building.remaining_supply > 0))
	return building.colony_owned

func prey(cell: Vector2i) -> Building:
	var target: Building
	var best := INF
	for building in world.registry.all():
		if not is_spider_target(building):
			continue
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
		if not is_spider_target(building):
			return
		_health[building] -= amount
		if _health[building] <= 0: _destroy(building)
	queue_redraw()
	changed.emit()

func _destroy(building: Building) -> void:
	if building is Workplace and not building.colony_owned:
		var improvement_id: StringName = building.improvement.id
		building.remove_improvement()
		world.planner.queue_workplace_refresh()
		world.prices.record(GameEvents.Kind.BUILDING_DEMOLISHED, improvement_id)
		world.build_controller.changed.emit()
		return
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

func restore_building_health(building: Building, value: int) -> void:
	_health[building] = value
