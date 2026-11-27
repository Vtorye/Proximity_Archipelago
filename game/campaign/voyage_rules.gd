class_name VoyageRules
extends Resource

@export var ship: SceneBuildOption
@export_range(1, 100, 1, "or_greater") var ship_unlock_level := 5

@export_group("Island Generation")
@export_range(1, 2147483647) var random_seed_max := 1000000000

@export_group("Scoring")
@export_range(0, 1000, 1, "or_greater") var points_per_task := 100
@export_range(0, 1000, 1, "or_greater") var points_per_island := 500

@export_group("Difficulty")
@export_range(0.0, 60.0, 0.1, "or_greater") var match_time_reduction := 10.0
@export_range(1.0, 600.0, 0.1, "or_greater") var minimum_match_time := 90.0
@export_range(0.0, 60.0, 0.1, "or_greater") var wave_interval_reduction := 5.0
@export_range(1.0, 600.0, 0.1, "or_greater") var minimum_wave_interval := 20.0
