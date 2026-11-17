class_name IslandGenerator
extends RefCounted
## Deterministic map data, editable and saveable through the existing level editor.

const NEST_ID := &"base_nest"
# These identifiers and the three biome indices are part of the saved layout format.
const MATERIAL_SITES := ["Workplace", "Workplace2", "AppleTree"]
const BIOME_SOILS := [&"fertile", &"dry", &"rocky"]
const CARDINALS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]

## A negative extent selects the authored default. Negative budgets use their authored values.
static func generate_data(template: World, seed_value: int, difficulty := 0, biome := 0, extent := -1, budgets := Vector3i(-1, -1, -1)) -> LevelData:
	var rules := template.island_generation
	var map := template.map as TerrainMap
	if rules == null or not rules.is_valid() or map == null or map.catalog == null:
		return null
	extent = clampi(rules.default_extent if extent < 0 else extent, rules.extent_limits.x, rules.extent_limits.y)
	for kind in range(MATERIAL_SITES.size()):
		if budgets[kind] < 0:
			budgets[kind] = rules.deposit_budgets[kind]
	var soil := map.catalog.by_id(&"soil")
	var water := map.catalog.by_id(&"water")
	if soil == null or water == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var center := Vector2i(extent / 2, extent / 2)
	var layout := LevelData.new()
	var land := _paint_land(layout, rules, rng, center, extent, soil.tile, water.tile)
	var occupied: Dictionary[Vector2i, bool] = {}
	if not _place_start(layout, template, rules, rng, center, land, occupied):
		return null
	var biome_index := clampi(biome, 0, BIOME_SOILS.size() - 1)
	var favored: int = [rules.fertile_favored_deposit, rules.dry_favored_deposit, rules.rocky_favored_deposit][biome_index]
	if not _place_deposits(layout, rules, rng, center, land, occupied, budgets, difficulty, favored):
		return null
	var result := _apply_soils(layout, rules, rng, seed_value, biome_index, center, land, occupied)
	if result == null:
		return null
	result.generated = true
	result.seed_value = seed_value
	result.difficulty = difficulty
	result.biome = biome
	result.title = TranslationServer.translate("ui.world.generated_title") % seed_value
	return result

static func _paint_land(layout: LevelData, rules: IslandGenerationRules, rng: RandomNumberGenerator, center: Vector2i, extent: int, soil: Vector4i, water: Vector4i) -> Dictionary[Vector2i, bool]:
	var noise := FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = rules.coast_noise_frequency
	var land: Dictionary[Vector2i, bool] = {}
	var lobes: Array[Vector3] = [Vector3(center.x, center.y, extent * rules.central_radius_ratio)]
	for index in range(rules.outer_island_count):
		var angle := TAU * index / rules.outer_island_count + rng.randf_range(-rules.outer_angle_jitter, rules.outer_angle_jitter)
		var point := Vector2(center) + Vector2.from_angle(angle) * extent * rules.outer_distance_ratio
		var radius := rng.randf_range(rules.outer_radius_ratios.x, rules.outer_radius_ratios.y) * extent
		lobes.append(Vector3(point.x, point.y, radius))
	var protected_radius_squared := rules.guaranteed_land_radius * rules.guaranteed_land_radius
	for y in range(extent):
		for x in range(extent):
			var cell := Vector2i(x, y)
			var value := -INF
			for lobe in lobes:
				var distance := Vector2(x - lobe.x, (y - lobe.y) * rules.vertical_scale).length()
				value = maxf(value, 1.0 - distance / lobe.z)
			if value + noise.get_noise_2d(x, y) * rules.coast_noise_strength > 0 or (cell - center).length_squared() < protected_radius_squared:
				land[cell] = true
			layout.tiles[cell] = soil if land.has(cell) else water
	return land

static func _place_start(layout: LevelData, template: World, rules: IslandGenerationRules, rng: RandomNumberGenerator, center: Vector2i, land: Dictionary[Vector2i, bool], occupied: Dictionary[Vector2i, bool]) -> bool:
	var nest: SceneBuildOption
	for option in template.build_controller.initial_options():
		if option is SceneBuildOption and option.id == NEST_ID:
			nest = option
			break
	if nest == null:
		return false
	for offset in nest.occupied_cells:
		var cell := center + offset
		if not land.has(cell):
			return false
		occupied[cell] = true
	var canteen := center + CARDINALS[rng.randi_range(0, CARDINALS.size() - 1)] * rules.canteen_distance
	if not land.has(canteen) or occupied.has(canteen):
		return false
	layout.objects.append(LevelData.Placement.new(center, "build/" + String(NEST_ID)))
	layout.objects.append(LevelData.Placement.new(canteen, "Food"))
	occupied[canteen] = true
	return true

static func _place_deposits(layout: LevelData, rules: IslandGenerationRules, rng: RandomNumberGenerator, center: Vector2i, land: Dictionary[Vector2i, bool], occupied: Dictionary[Vector2i, bool], budgets: Vector3i, difficulty: int, favored: int) -> bool:
	var distance_difficulty := clampi(difficulty, 0, rules.max_distance_difficulty)
	var search_radius := rules.deposit_distance.y
	for deposit in range(rules.starter_deposits_per_resource * MATERIAL_SITES.size()):
		var kind := deposit % MATERIAL_SITES.size()
		var minimum := rules.deposit_distance.x
		if deposit < MATERIAL_SITES.size():
			minimum = rules.favored_deposit_distance if kind == favored else minimum + distance_difficulty
		var maximum := search_radius + distance_difficulty
		var candidates: Array[Vector2i] = []
		for y in range(-search_radius, search_radius + 1):
			for x in range(-search_radius, search_radius + 1):
				var cell := center + Vector2i(x, y)
				var distance := absi(x) + absi(y)
				if distance >= minimum and distance <= maximum and land.has(cell) and not occupied.has(cell):
					candidates.append(cell)
		if candidates.is_empty():
			for cell in land:
				var distance := absi(cell.x - center.x) + absi(cell.y - center.y)
				if distance >= minimum and not occupied.has(cell):
					candidates.append(cell)
		if candidates.is_empty():
			return false
		var cell := candidates[rng.randi_range(0, candidates.size() - 1)]
		var supply := maxi(rules.minimum_starter_supply, rng.randi_range(rules.starter_supply_range.x, rules.starter_supply_range.y) - difficulty * rules.starter_supply_loss_per_island)
		supply = mini(budgets[kind], supply + (rules.favored_supply_bonus if kind == favored else 0))
		budgets[kind] -= supply
		layout.objects.append(LevelData.Placement.new(cell, MATERIAL_SITES[kind], supply, true))
		occupied[cell] = true
		if kind == 0 and supply > rules.wide_timber_threshold:
			occupied[cell + Vector2i.RIGHT] = true
	var protected_radius_squared := rules.guaranteed_land_radius * rules.guaranteed_land_radius
	var extra_supply := maxi(rules.minimum_extra_supply, rules.extra_deposit_supply - difficulty * rules.extra_supply_loss_per_island)
	for cell in land:
		if (cell - center).length_squared() < protected_radius_squared or occupied.has(cell) or rng.randf() > rules.extra_deposit_chance:
			continue
		var kind := rng.randi_range(0, MATERIAL_SITES.size() - 1)
		var supply := mini(budgets[kind], extra_supply)
		if supply > 0:
			layout.objects.append(LevelData.Placement.new(cell, MATERIAL_SITES[kind], supply, true))
			budgets[kind] -= supply
	return true

static func _apply_soils(layout: LevelData, rules: IslandGenerationRules, rng: RandomNumberGenerator, seed_value: int, biome: int, center: Vector2i, land: Dictionary[Vector2i, bool], occupied: Dictionary[Vector2i, bool]) -> LevelData:
	var world := LevelLayout.instantiate_world(layout)
	if world == null:
		return null
	var map := world.map as TerrainMap
	var buildings := world.placed_buildings()
	var nodes: Array[Node] = []
	nodes.assign(buildings)
	TerrainPainter.populate(map, nodes, rules, seed_value)
	var preferred := map.catalog.by_id(BIOME_SOILS[biome])
	if preferred != null:
		var chance: float = [rules.fertile_bias, rules.dry_bias, rules.rocky_bias][biome]
		var radius_squared := rules.biome_protection_radius * rules.biome_protection_radius
		var protected: Dictionary[Vector2i, int] = {}
		for building in buildings:
			for cell in building.footprint():
				protected[cell] = TerrainRules.building_kind(building)
		for cell in land:
			if occupied.has(cell) or (cell - center).length_squared() < radius_squared:
				continue
			var ground := map.ground_at(cell)
			if ground != null and ground.kind == TerrainType.Kind.LAND and rng.randf() < chance and TerrainRules.supports(preferred, protected.get(cell, BuildOption.PlacementKind.ANY)):
				map.paint_tile(cell, preferred.tile, true)
	var result := LevelLayout.capture_data(map, nodes)
	world.free()
	return result
