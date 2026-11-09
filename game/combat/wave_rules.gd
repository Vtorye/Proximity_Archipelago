class_name WaveRules
extends Resource
## All experimental combat numbers are editable without changing agent logic.
@export_range(1.0, 600.0) var first_wave_seconds := 45.0
@export_range(1.0, 600.0) var wave_interval_seconds := 60.0
@export_range(1.0, 100.0) var minimum_shore_distance_cells := 8.0
@export_range(1.0, 300.0) var maximum_shore_approach_seconds := 30.0
@export_range(1, 50) var initial_spiders := 2
@export_range(0, 10) var spiders_per_wave := 1
@export_range(1, 100) var maximum_spiders := 20
@export_range(1, 100) var warrior_health := 4
@export_range(1, 100) var spider_health := 6
@export_range(1, 100) var attack_damage := 1
@export_range(0.1, 10.0) var attack_seconds := 1.0
@export_range(1.0, 128.0) var spider_speed := 18.0
@export_range(1.0, 20.0) var detection_cells := 5.0
@export_range(1, 1000) var wall_health := 20
@export_range(1, 1000) var tower_health := 12
@export_range(1, 1000) var nest_health := 30
@export_range(1, 1000) var building_health := 8
@export_range(1.0, 20.0) var tower_range_cells := 6.0
@export_range(0.1, 10.0) var tower_shot_seconds := 0.8
@export_range(1.0, 120.0) var sabotage_seconds := 10.0
@export var trap_removal_costs: Array[ResourceAmount] = []
@export var ruined_road: TileBuildOption
@export var defenses: BuildCatalog

func validate() -> Array[String]:
	var errors: Array[String] = []
	for field in ["first_wave_seconds", "wave_interval_seconds", "minimum_shore_distance_cells", "maximum_shore_approach_seconds", "initial_spiders", "maximum_spiders", "warrior_health", "spider_health", "attack_damage", "attack_seconds", "spider_speed", "detection_cells", "wall_health", "tower_health", "nest_health", "building_health", "tower_range_cells", "tower_shot_seconds", "sabotage_seconds"]:
		var value: float = float(get(field))
		if not is_finite(value) or value <= 0: errors.append("%s must be finite and positive" % field)
	if spiders_per_wave < 0 or maximum_spiders < initial_spiders: errors.append("invalid wave population limits")
	if defenses == null or defenses.options.is_empty(): errors.append("missing defense catalog")
	if ruined_road == null: errors.append("missing ruined-road terrain")
	for item in trap_removal_costs:
		if item == null or item.type == null or item.amount < 0: errors.append("invalid trap-removal price")
	return errors
