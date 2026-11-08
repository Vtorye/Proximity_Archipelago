class_name Voyage
extends RefCounted
## Travel carries colony wealth and permanent upgrades, while each island starts a new task ladder.
var world: World
var island := 1
var seed_value := 1
var score := 0
var offers: Array[Dictionary] = []
var departed := false
const SHIP = preload("res://game/campaign/ship.tres")

func configure(colony: World) -> void:
	world = colony
	seed_value = randi_range(1, 1000000000)
	world.tasks.changed.connect(refresh)
	world.registry.added.connect(_built)
	refresh()

func refresh() -> void:
	if world.tasks.level >= 5 and not world.build_controller.options.has(SHIP):
		world.build_controller.options.append(SHIP)
		world.tasks.message = TranslationServer.translate("ui.voyage.ship_unlocked")
		world.prices.definitions = world.build_controller.options.duplicate()
		world.prices.changed.emit()

func _built(building: Building) -> void:
	if building.option == null or building.option.id != &"ship" or building is ConstructionSite or departed: return
	departed = true
	score += world.tasks.completed_count * 100 + maxi(0, roundi(world.match_controller.time_remaining)) + island * 500
	offers.clear()
	for index in range(3):
		offers.append({"seed": seed_value + island * 7919 + index * 1543, "difficulty": island, "biome": index})
	world.match_controller.complete_objective()

func travel(index: int) -> Dictionary:
	if not departed or index < 0 or index >= offers.size(): return {}
	var choice: Dictionary = offers[index]
	var layout: Dictionary = IslandGenerator.generate(choice.seed, choice.difficulty, choice.biome)
	layout["journey"] = {"island": island + 1, "seed": choice.seed, "score": score, "wealth": wealth(), "buffs": world.tasks.buffs.duplicate()}
	layout["wave_mode"] = world.combat != null
	return layout

func wealth() -> Dictionary:
	var result := {}
	for type in world.inventory.registered_types(): result[str(type.id)] = world.inventory.quantity(type)
	return result

func apply(data: Dictionary) -> void:
	island = int(data.get("island", 1))
	seed_value = int(data.get("seed", 1))
	score = int(data.get("score", 0))
	for id in data.get("wealth", {}):
		var type: ResourceType = world.inventory.type_by_id(StringName(id))
		if type != null:
			var difference: int = int(data.wealth[id]) - world.inventory.quantity(type)
			if difference >= 0: world.inventory.add(type, difference)
			else: world.inventory._withdraw(type.id, -difference)
	for buff in data.get("buffs", []): world.tasks.grant_buff(int(buff))
	world.match_controller.match_duration = maxf(90.0, 180.0 - (island - 1) * 10.0)
	world.tasks.difficulty_multiplier = 1.0 + (island - 1) * 0.2
	if world.combat != null:
		world.combat.rules = world.combat.rules.duplicate()
		world.combat.rules.wave_interval_seconds = maxf(20.0, 60.0 - (island - 1) * 5.0)
