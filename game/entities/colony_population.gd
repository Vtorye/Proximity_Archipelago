class_name ColonyPopulation
extends Node
## Owns spawning, homes, and removal; buildings do not create or destroy agents.

signal changed
signal spawned(agent: AntAgent)
signal cell_changed(old: Vector2i, next: Vector2i)
var units: Node2D
var navigation: RouteService
var planner: TripPlanner
var logistics: ColonyLogistics
var construction: ConstructionService
var recruitment: RecruitmentCatalog
var _recruiting := false
var _removing := false

func configure(root: Node2D, routes: RouteService, policy: TripPlanner, registry: BuildingRegistry, storage: ColonyLogistics) -> void:
	units = root
	navigation = routes
	planner = policy
	logistics = storage
	registry.added.connect(_on_building_added)
	registry.removed.connect(_on_building_removed)

func _on_building_added(building: Building) -> void:
	if not building is House:
		return
	var house: House = building as House
	var entry: Vector2i = planner.accessible_entry(house)
	if not navigation.walkable(entry):
		return
	var initial_count: int = mini(house.capacity, house.resident_limit())
	for index in range(initial_count):
		var role: AntAgent.Role = AntAgent.Role.CARRIER if initial_count > 1 and index == initial_count - 1 else AntAgent.Role.WORKER
		var ant: AntAgent = _create_resident(house, role)
		if ant == null:
			push_error("Nest scene must contain an AntAgent root")
			return
		ant.departure_delay = index * 1.25
		_add_resident(house, ant)
	changed.emit()

func can_recruit(house: House, role: AntAgent.Role) -> bool:
	return (
		not _recruiting and not _removing and recruitment != null and logistics.owns(house)
		and role in [AntAgent.Role.WORKER, AntAgent.Role.CARRIER]
		and house.has_space() and navigation.walkable(planner.accessible_entry(house))
		and planner.inventory.can_afford_all(recruitment.price(role), true)
	)

func recruit(house: House, role: AntAgent.Role) -> bool:
	if not can_recruit(house, role):
		return false
	var ant: AntAgent = _create_resident(house, role)
	if ant == null:
		return false
	_recruiting = true
	planner.inventory.begin_update()
	if not planner.inventory.try_spend_all(recruitment.price(role), true):
		ant.free()
		_recruiting = false
		planner.inventory.end_update()
		return false
	_add_resident(house, ant)
	_recruiting = false
	planner.inventory.end_update()
	changed.emit()
	return true

func kill_resident(house: House, role: AntAgent.Role) -> bool:
	if _recruiting or _removing or not logistics.owns(house):
		return false
	for ant: AntAgent in house.residents:
		if ant.home == house and ant.role == role and ant.status != AntAgent.Status.DEAD and ant.get_parent() == units:
			_removing = true
			ant.die(AntAgent.DeathCause.PLAYER)
			_removing = false
			changed.emit()
			return true
	return false

func _create_resident(house: House, role: AntAgent.Role) -> AntAgent:
	if house.human_scene == null:
		return null
	var instance: Node = house.human_scene.instantiate()
	if not instance is AntAgent:
		instance.free()
		return null
	var ant: AntAgent = instance as AntAgent
	ant.role = role
	if house.option is SceneBuildOption and house.option.spawn_count > 0:
		ant.speed = house.option.spawn_speed
	if role == AntAgent.Role.CARRIER:
		ant.speed *= house.carrier_speed_multiplier
		ant.carry_capacity = house.carrier_capacity
	ant.configure(house, planner, navigation, logistics)
	if construction != null:
		ant.construction = AntConstruction.new()
		ant.construction.ant = ant
		ant.construction.service = construction
	return ant

func _add_resident(house: House, ant: AntAgent) -> void:
	var entry: Vector2i = planner.accessible_entry(house)
	house.add_resident(ant)
	ant.position = units.to_local(navigation.cell_to_world(entry))
	units.add_child(ant)
	ant.cell_changed.connect(func(old: Vector2i, next: Vector2i): cell_changed.emit(old, next))
	ant.status_changed.connect(func(_status: AntAgent.Status): changed.emit())
	ant.waiting_changed.connect(func(): changed.emit())
	ant.died.connect(func(_ant: Node2D, _cause: int): changed.emit())
	spawned.emit(ant)

func _on_building_removed(building: Building) -> void:
	if building is House:
		for resident in building.residents:
			if is_instance_valid(resident) and resident is AntAgent:
				resident.die(AntAgent.DeathCause.DEMOLISHED)
	elif building is Workplace:
		for ant in agents():
			ant.workplace_removed(building)
	changed.emit()

func count() -> int:
	return agents().size()

func agents() -> Array[AntAgent]:
	var result: Array[AntAgent] = []
	for child in units.get_children():
		if child is AntAgent and child.status != AntAgent.Status.DEAD:
			result.append(child)
	return result
