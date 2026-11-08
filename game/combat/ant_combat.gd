class_name AntCombat
extends RefCounted
## Civilian escape and warrior duty never reserve production slots.
var ant: AntAgent
var director: CombatDirector
var tower: DefenseBuilding
var _enemy: SpiderAgent
var _attack := 0.0
var _rethink := 0.0
var _patrol: Building
var _visited: Dictionary[Building, int] = {}
var _visit := 0

func physics(delta: float) -> bool:
	if not director.running(): return false
	_attack = maxf(0.0, _attack - delta)
	_rethink -= delta
	if ant.role != AntAgent.Role.WARRIOR: return _civilian()
	if ant.status == AntAgent.Status.EATING or (ant.status == AntAgent.Status.WALKING and ant._destination == &"combat_meal"): return false
	if _meal_due():
		if ant.status != AntAgent.Status.WAITING_FOR_FOOD: seek_meal()
		return false
	if ant.status == AntAgent.Status.GUARDING:
		if not is_instance_valid(tower) or tower.gunner != ant:
			leave_tower()
			decide()
		return true
	if ant.status == AntAgent.Status.FIGHTING:
		if not director.alive(_enemy):
			decide()
			return false
		if director.can_melee(ant.global_position, _enemy):
			if _attack <= 0:
				director.damage(_enemy, ant.attack_damage)
				_attack = director.rules.attack_seconds
			return true
		_chase(_enemy)
	elif ant.status == AntAgent.Status.WALKING and ant._destination == &"combat_chase":
		if not director.alive(_enemy): decide()
		elif director.can_melee(ant.global_position, _enemy):
			ant._set_status(AntAgent.Status.FIGHTING)
			return true
		elif _rethink <= 0:
			_chase(_enemy)
	elif tower == null and _rethink <= 0 and ant.status != AntAgent.Status.WAITING_FOR_FOOD:
		var enemy: SpiderAgent = _reachable_enemy()
		_rethink = 0.5
		if enemy != null: _chase(enemy)
		elif ant._destination == &"combat_patrol":
			for building in director.world.registry.all():
				if building is DefenseBuilding and building.kind == DefenseBuilding.Kind.TOWER and not is_instance_valid(building.gunner):
					decide()
					break
	return false

func _civilian() -> bool:
	var threat: SpiderAgent = director.nearest_spider(ant.global_position, director.rules.detection_cells)
	if threat == null: return false
	if ant.status == AntAgent.Status.WALKING and ant._destination == &"flee" and _rethink > 0: return false
	_rethink = 0.4
	var navigation: RouteService = ant.route_service
	var cell: Vector2i = navigation.world_to_cell(ant.global_position)
	var escape := cell
	var distance: float = ant.global_position.distance_squared_to(threat.global_position)
	for next in navigation.snapshot().neighbors(cell):
		var value: float = navigation.cell_to_world(next).distance_squared_to(threat.global_position)
		if value > distance:
			distance = value
			escape = next
	ant._release_work()
	if ant.construction != null and ant.construction.job != null and not ant.construction.has_cargo(): ant.construction.release()
	if escape != cell:
		ant._walk(navigation.make_route([cell, escape]), &"flee")
	else:
		# A cornered civilian may defend itself, but never approaches a spider to attack.
		if _attack <= 0 and director.can_melee(ant.global_position, threat):
			director.damage(threat, ant.attack_damage)
			_attack = director.rules.attack_seconds
		ant._set_status(AntAgent.Status.WANDERING)
		ant._timer = 0.3
	return false

func decide() -> void:
	ant._release_work()
	ant._waiting_for_work = false
	ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
	if _meal_due():
		seek_meal()
		return
	if is_instance_valid(tower):
		var route: Route = director.approach(tower, _cell())
		if route.is_valid():
			ant._walk(route, &"combat_tower")
			return
		leave_tower()
	# An unstaffed tower reserves this warrior before the next warrior chooses its duty.
	var best: DefenseBuilding
	var approach: Route
	var lowest := INF
	for building in director.world.registry.all():
		if not building is DefenseBuilding or building.kind != DefenseBuilding.Kind.TOWER or is_instance_valid(building.gunner): continue
		var route: Route = director.approach(building, _cell())
		if route.is_valid() and route.cost < lowest and ant.needs.can_afford(ant.planner.travel_energy(route.cost, ant.speed) + _home_energy(route.cells.back()) + 4.0):
			best = building
			approach = route
			lowest = route.cost
	if best != null:
		tower = best
		best.gunner = ant
		ant._walk(approach, &"combat_tower")
		return
	var enemy: SpiderAgent = _reachable_enemy()
	if enemy != null and _chase(enemy): return
	_enemy = null
	if not _patrol_next(): ant._wander()

func _chase(enemy: SpiderAgent) -> bool:
	var route: Route = director.approach(enemy, _cell())
	if not route.is_valid(): return false
	var energy: float = ant.planner.travel_energy(route.cost, ant.speed) + _home_energy(route.cells.back())
	if energy + 4.0 + AntNeeds.SAFETY_MARGIN > ant.needs.capacity: return false
	if not ant.needs.can_afford(energy + 4.0):
		seek_meal()
		return true
	leave_tower()
	_enemy = enemy
	_rethink = 0.5
	ant._walk(route, &"combat_chase")
	return true

func _reachable_enemy() -> SpiderAgent:
	var best: SpiderAgent
	var lowest := INF
	for spider in director.spiders:
		var distance: float = ant.global_position.distance_squared_to(spider.global_position)
		if distance < lowest and ant.route_service.snapshot().connected(_cell(), ant.route_service.world_to_cell(spider.global_position)):
			lowest = distance
			best = spider
	return best

func _meal_due() -> bool:
	return ant.needs.satiety <= maxf(ant.needs.capacity * (ant.profile.meal_fraction if ant.profile != null else 0.5), _home_energy(_cell()) + AntNeeds.SAFETY_MARGIN + 4.0)

func _patrol_next() -> bool:
	var best: Building
	var route: Route
	var oldest := 2147483647
	var cost := INF
	for building in director.world.registry.all():
		if not (building is Workplace or building is House or building is Canteen) or building == _patrol: continue
		var path: Route = director.approach(building, _cell())
		if not path.is_valid() or path.cost < 0.01: continue
		var energy: float = ant.planner.travel_energy(path.cost, ant.speed) + _home_energy(path.cells.back()) + 4.0
		if not ant.needs.can_afford(energy): continue
		var visited: int = _visited.get(building, 0)
		if visited < oldest or (visited == oldest and path.cost < cost):
			best = building
			route = path
			oldest = visited
			cost = path.cost
	if best == null: return false
	_patrol = best
	_visit += 1
	_visited[best] = _visit
	ant._walk(route, &"combat_patrol")
	return true

func _home_energy(cell: Vector2i) -> float:
	var route: Route = ant.logistics.route_to(ant.home, cell)
	return ant.planner.travel_energy(route.cost, ant.speed) if route.is_valid() else INF

func seek_meal() -> void:
	leave_tower()
	_enemy = null
	ant.refresh_meal_reservation()
	# Warriors eat at their nest, including on islands without a canteen.
	if ant._meal == null or not ant._meal.active: ant._meal = ant.planner.reserve_meal()
	var route: Route = ant.logistics.route_to(ant.home, _cell())
	if ant._meal == null or not route.is_valid():
		ant._set_status(AntAgent.Status.WAITING_FOR_FOOD)
		ant._timer = 1.0
	else:
		ant._walk(route, &"combat_meal")

func arrive(destination: StringName) -> void:
	if destination == &"combat_meal":
		ant._set_status(AntAgent.Status.EATING)
		ant._timer = AntNeeds.MEAL_SECONDS
	elif destination == &"combat_tower" and is_instance_valid(tower) and tower.gunner == ant:
		ant._set_status(AntAgent.Status.GUARDING)
	else:
		decide()

func leave_tower() -> void:
	if is_instance_valid(tower) and tower.gunner == ant: tower.gunner = null
	tower = null

func navigation_changed() -> void:
	_rethink = 0
	if ant.status == AntAgent.Status.EATING: return
	if ant.role == AntAgent.Role.WARRIOR: decide()

func _cell() -> Vector2i:
	return ant.route_service.world_to_cell(ant.global_position)
