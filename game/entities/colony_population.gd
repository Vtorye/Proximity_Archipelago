class_name ColonyPopulation
extends Node
## Owns spawning, homes, and removal; buildings do not create or destroy agents.

signal changed
signal cell_changed(old: Vector2i, next: Vector2i)
var units: Node2D
var navigation: RouteService
var planner: TripPlanner

func configure(root: Node2D, routes: RouteService, policy: TripPlanner, registry: BuildingRegistry) -> void:
	units = root
	navigation = routes
	planner = policy
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
		ant.configure(house, planner, navigation)
		house.add_resident(ant)
		units.add_child(ant)
		ant.global_position = navigation.cell_to_world(entry)
		ant.cell_changed.connect(func(old: Vector2i, next: Vector2i): cell_changed.emit(old, next))
		ant.died.connect(func(_ant: Node2D, _cause: int): changed.emit())
	changed.emit()

func _on_building_removed(building: Building) -> void:
	if building is House:
		for resident in building.residents:
			if is_instance_valid(resident) and resident is AntAgent:
				resident.die(AntAgent.DeathCause.DEMOLISHED)
	changed.emit()

func count() -> int:
	return agents().size()

func agents() -> Array[AntAgent]:
	var result: Array[AntAgent] = []
	for child in units.get_children():
		if child is AntAgent and child.status != AntAgent.Status.DEAD:
			result.append(child)
	return result
