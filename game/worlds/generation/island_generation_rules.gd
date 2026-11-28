class_name IslandGenerationRules
extends Resource
## Shared settings for new games, editor generation and voyage destinations.

@export_group("Map Size")
@export var default_extent := 80
@export var extent_limits := Vector2i(40, 160)
@export var editor_extents := PackedInt32Array([50, 80, 120, 160])

@export_group("Island Shape")
@export_range(0.001, 1.0, 0.001) var coast_noise_frequency := 0.1
@export_range(0.0, 1.0, 0.01) var coast_noise_strength := 0.28
@export_range(0.01, 0.5, 0.01) var central_radius_ratio := 0.24
@export_range(1, 32) var outer_island_count := 7
@export_range(0.01, 0.5, 0.01) var outer_distance_ratio := 0.4
@export var outer_radius_ratios := Vector2(0.045, 0.08)
@export_range(0.0, 1.0, 0.01, "radians_as_degrees") var outer_angle_jitter := 0.2
@export_range(0.1, 3.0, 0.01) var vertical_scale := 1.12
@export_range(2, 64) var guaranteed_land_radius := 9
@export_range(1, 64) var canteen_distance := 3

@export_group("Deposits")
## The three budgets are wood, stone and berries, in that order.
@export var deposit_budgets := Vector3i(900, 900, 900)
@export_range(1, 8) var starter_deposits_per_resource := 2
@export var deposit_distance := Vector2i(7, 12)
@export_range(1, 64) var favored_deposit_distance := 6
@export_range(0, 20) var max_distance_difficulty := 2
@export var starter_supply_range := Vector2i(130, 220)
@export_range(0, 100000) var minimum_starter_supply := 60
@export_range(0, 100000) var starter_supply_loss_per_island := 10
@export_range(0, 100000) var favored_supply_bonus := 55
## A large timber stand reserves an extra tile to its east when placing the other deposits.
@export_range(0, 100000) var wide_timber_threshold := 200
@export_range(0.0, 1.0, 0.001) var extra_deposit_chance := 0.025
@export_range(0, 100000) var extra_deposit_supply := 140
@export_range(0, 100000) var minimum_extra_supply := 20
@export_range(0, 100000) var extra_supply_loss_per_island := 12

@export_group("Biome Bias")
@export_range(0.0, 1.0, 0.01) var fertile_bias := 0.06
@export_range(0.0, 1.0, 0.01) var dry_bias := 0.22
@export_range(0.0, 1.0, 0.01) var rocky_bias := 0.08
@export_enum("Wood", "Stone", "Berries") var fertile_favored_deposit := 2
@export_enum("Wood", "Stone", "Berries") var dry_favored_deposit := 0
@export_enum("Wood", "Stone", "Berries") var rocky_favored_deposit := 1
@export_range(0, 64) var biome_protection_radius := 6

@export_group("Soil Distribution")
@export var soil_seed := 814
@export_range(0.001, 1.0, 0.001) var soil_noise_frequency := 0.09
@export_range(1, 10) var soil_noise_octaves := 2
@export_range(1, 64) var wet_shore_depth := 2
@export_range(1, 64) var dry_inland_distance := 5
@export_range(1, 64) var dry_nest_distance := 4
@export_range(0.0, 10.0, 0.01) var quarry_soil_radius := sqrt(2.0)
@export_range(-1.0, 1.0, 0.01) var sand_threshold := 0.1
@export_range(-1.0, 1.0, 0.01) var dry_threshold := 0.08
@export_range(-1.0, 1.0, 0.01) var fertile_threshold := -0.45

func is_valid() -> bool:
	return (
		extent_limits.x > 0 and extent_limits.y >= extent_limits.x
		and extent_limits.y <= floori(sqrt(LevelLayout.TILE_LIMIT))
		and central_radius_ratio > 0.0 and outer_island_count >= 0
		and outer_radius_ratios.x > 0.0 and outer_radius_ratios.y >= outer_radius_ratios.x
		and guaranteed_land_radius > canteen_distance and canteen_distance > 0
		and deposit_budgets.x >= 0 and deposit_budgets.y >= 0 and deposit_budgets.z >= 0
		and starter_deposits_per_resource > 0
		and deposit_distance.x > 0 and deposit_distance.y >= deposit_distance.x
		and deposit_distance.y <= extent_limits.y
		and starter_supply_range.x >= 0 and starter_supply_range.y >= starter_supply_range.x)
