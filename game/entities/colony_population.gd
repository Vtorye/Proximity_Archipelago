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
	for index in range(house.capacity):
		var instance: Node = house.human_scene.instantiate()
		if not instance is AntAgent:
			instance.free()
			push_error("Nest scene must contain an AntAgent root")
			return
		var ant: AntAgent = instance as AntAgent
		if house.option is SceneBuildOption and house.option.spawn_count > 0:
			ant.speed = house.option.spawn_speed
		if house.capacity > 1 and index == house.capacity - 1:
			ant.role = AntAgent.Role.CARRIER
			ant.speed *= house.carrier_speed_multiplier
			ant.carry_capacity = house.carrier_capacity
		ant.departure_delay = index * 1.25
		ant.configure(house, planner, navigation, logistics)
		house.add_resident(ant)
		ant.position = units.to_local(navigation.cell_to_world(entry))
		units.add_child(ant)
		ant.cell_changed.connect(func(old: Vector2i, next: Vector2i): cell_changed.emit(old, next))
		ant.status_changed.connect(func(_status: AntAgent.Status): changed.emit())
		ant.waiting_changed.connect(func(): changed.emit())
		ant.died.connect(func(_ant: Node2D, _cause: int): changed.emit())
		spawned.emit(ant)
	changed.emit()

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
