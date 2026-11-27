class_name Voyage
extends RefCounted
## Travel carries colony wealth and permanent upgrades, while each island starts a new task ladder.
var world: World
var island := 1
var seed_value := 1
var score := 0
var offers: Array[Dictionary] = []
var departed := false
var requires_evacuation := false
var travelling_characters: Array[String] = []
var departure_manifest: Dictionary = {}
var _destinations: Dictionary[int, LevelData] = {}
var _rules: VoyageRules

func configure(colony: World, rules: VoyageRules) -> void:
	world = colony
	_rules = rules
	seed_value = randi_range(1, 1000000000)
	world.tasks.changed.connect(refresh)
	world.registry.added.connect(_built)
	refresh()

func refresh() -> void:
	if world.tasks.level >= _rules.ship_unlock_level and world.build_controller.unlock_option(_rules.ship):
		world.tasks.message = "ui.voyage.ship_unlocked"

func _built(building: Building) -> void:
	if _rules.ship == null or building.option == null or building.option.id != _rules.ship.id or building is ConstructionSite or departed: return
	if requires_evacuation:
		return
	complete_departure()

func complete_departure() -> void:
	if departed:
		return
	departed = true
	score += world.tasks.completed_count * _rules.points_per_task + maxi(0, roundi(world.match_controller.time_remaining)) + island * _rules.points_per_island
	offers.clear()
	for index in range(3):
		offers.append({"seed": seed_value + island * 7919 + index * 1543, "difficulty": island, "biome": index})
	world.match_controller.complete_objective()

func destination(index: int) -> Dictionary:
	var data: LevelData = destination_data(index)
	return LevelLayout.encode(data) if data != null else {}

func destination_data(index: int) -> LevelData:
	if not departed or index < 0 or index >= offers.size():
		return null
	if not _destinations.has(index):
		var choice: Dictionary = offers[index]
		_destinations[index] = IslandGenerator.generate_data(world, choice.seed, choice.difficulty, choice.biome)
	return _destinations[index]

func travel(index: int) -> Dictionary:
	var layout: Dictionary = destination(index).duplicate()
	if layout.is_empty():
		return {}
	var choice: Dictionary = offers[index]
	layout["journey"] = {"island": island + 1, "seed": choice.seed, "score": score, "wealth": wealth(), "buffs": world.tasks.buffs.duplicate()}
	layout.journey["characters"] = travelling_characters.duplicate()
	layout["wave_mode"] = world.combat != null and not requires_evacuation
	return layout

func wealth() -> Dictionary:
	if requires_evacuation:
		return departure_manifest.duplicate()
	var result := {}
	for type in world.inventory.registered_types(): result[str(type.id)] = world.inventory.quantity(type)
	return result

func apply(data: Dictionary) -> void:
	travelling_characters.assign(data.get("characters", []))
	island = int(data.get("island", 1))
	seed_value = int(data.get("seed", 1))
	score = int(data.get("score", 0))
	for id in data.get("wealth", {}):
		var type: ResourceType = world.inventory.type_by_id(StringName(id))
		if type != null:
			var difference: int = maxi(0, int(data.wealth[id])) - world.inventory.quantity(type)
			if difference >= 0:
				world.inventory.add(type, difference)
			else:
				var cost := ResourceAmount.new()
				cost.type = type
				cost.amount = -difference
				world.inventory.try_spend_all([cost], false, true)
	for buff in data.get("buffs", []): world.tasks.grant_buff(int(buff))
	var completed_islands := maxi(0, island - 1)
	world.match_controller.configure_duration_reduction(completed_islands * _rules.match_time_reduction, _rules.minimum_match_time)
	if world.combat != null:
		world.combat.configure_wave_interval_reduction(completed_islands * _rules.wave_interval_reduction, _rules.minimum_wave_interval)

func capture_state() -> Dictionary:
	return {
		"island": island, "seed_value": seed_value, "score": score,
		"departed": departed, "offers": offers.duplicate(true),
		"characters": travelling_characters.duplicate(),
		"evacuation": requires_evacuation, "manifest": departure_manifest.duplicate(),
	}

func restore_state(state: Dictionary) -> void:
	requires_evacuation = state.get("evacuation", false)
	departure_manifest = state.get("manifest", {}).duplicate()
	travelling_characters.assign(state.get("characters", []))
	island = state.island
	seed_value = state.seed_value
	score = state.score
	departed = state.departed
	offers.assign(state.offers.duplicate(true))
	_destinations.clear()
