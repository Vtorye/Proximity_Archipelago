class_name IslandGenerator
extends RefCounted
## Deterministic map data, editable and saveable through the existing level editor.
static func generate(seed_value: int, difficulty := 0, biome := 0, extent := 80) -> Dictionary:
	var data: LevelData = generate_data(seed_value, difficulty, biome, extent)
	return LevelLayout.encode(data) if data != null else {}

static func generate_data(seed_value: int, difficulty := 0, biome := 0, extent := 80, resource_totals: Dictionary = {}) -> LevelData:
	extent = clampi(extent, 40, 160)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var center := Vector2i(extent / 2, extent / 2)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.1
	var layout := LevelData.new()
	var land: Dictionary[Vector2i, bool] = {}
	var lobes: Array[Vector3] = [Vector3(center.x, center.y, extent * 0.24)]
	for index in range(7):
		var angle: float = TAU * index / 7.0 + rng.randf_range(-0.2, 0.2)
		var point: Vector2 = Vector2(center) + Vector2.from_angle(angle) * extent * 0.40
		lobes.append(Vector3(point.x, point.y, rng.randf_range(0.045, 0.08) * extent))
	for y in range(extent):
		for x in range(extent):
			var cell := Vector2i(x, y)
			var value := -INF
			for lobe in lobes:
				value = maxf(value, 1.0 - Vector2(x - lobe.x, (y - lobe.y) * 1.12).length() / lobe.z)
			if value + noise.get_noise_2d(x, y) * 0.28 > 0 or (cell - center).length_squared() < 81: land[cell] = true
			layout.tiles[cell] = Vector4i(3, 1 if land.has(cell) else 3, 0, 0)
	var canteen: Vector2i = center + [Vector2i(0, 3), Vector2i(3, 0), Vector2i(0, -3), Vector2i(-3, 0)][rng.randi_range(0, 3)]
	layout.objects.append(LevelData.Placement.new(center, "build/base_nest"))
	layout.objects.append(LevelData.Placement.new(canteen, "Food"))
	var occupied: Dictionary[Vector2i, bool] = {}
	for x in range(2):
		for y in range(2): occupied[center + Vector2i(x, y)] = true
	occupied[canteen] = true
	var kinds := ["Workplace", "Workplace2", "AppleTree"]
	var favored: int = [2, 0, 1][clampi(biome, 0, 2)]
	# The central land disk guarantees reachable, finite deposits. Seed and biome
	# determine where each kind appears and which resource is easiest to acquire.
	var totals := {"Workplace": int(resource_totals.get("Workplace", 900)), "Workplace2": int(resource_totals.get("Workplace2", 900)), "AppleTree": int(resource_totals.get("AppleTree", 900))}
	for deposit in range(6):
		var kind: int = deposit % kinds.size()
		var minimum: int = 7 if deposit >= 3 else (6 if kind == favored else 7 + clampi(difficulty, 0, 2))
		var maximum: int = 12 + clampi(difficulty, 0, 2)
		var candidates: Array[Vector2i] = []
		for y in range(-12, 13):
			for x in range(-12, 13):
				var offset := Vector2i(x, y)
				var distance: int = absi(x) + absi(y)
				var cell: Vector2i = center + offset
				if distance >= minimum and distance <= maximum and land.has(cell) and not occupied.has(cell):
					candidates.append(cell)
		if candidates.is_empty():
			for cell in land:
				var distance: int = absi(cell.x - center.x) + absi(cell.y - center.y)
				if distance >= minimum and land.has(cell) and not occupied.has(cell):
					candidates.append(cell)
		if candidates.is_empty():
			return null
		var cell: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		var supply: int = mini(int(totals[kinds[kind]]), maxi(60, rng.randi_range(130, 220) - difficulty * 10) + (55 if kind == favored else 0))
		totals[kinds[kind]] = int(totals[kinds[kind]]) - supply
		if kind == 0 and supply > 200:
			layout.objects.append(LevelData.Placement.new(cell, kinds[kind], supply, true))
			occupied[cell] = true
			occupied[cell + Vector2i.RIGHT] = true
			continue
		layout.objects.append(LevelData.Placement.new(cell, kinds[kind], supply, true))
		occupied[cell] = true
	for cell in land:
		if (cell - center).length_squared() < 81 or occupied.has(cell) or rng.randf() > 0.025: continue
		var kind: String = kinds[rng.randi_range(0, 2)]
		var kind_supply: int = mini(int(totals[kind]), maxi(20, 140 - difficulty * 12))
		if kind_supply <= 0: continue
		layout.objects.append(LevelData.Placement.new(cell, kind, kind_supply, true))
		totals[kind] = int(totals[kind]) - kind_supply
	var world: World = LevelLayout.instantiate_world(layout)
	if world == null:
		return null
	var map := world.map as TerrainMap
	var buildings: Array[Building] = world.placed_buildings()
	var nodes: Array[Node] = []
	nodes.assign(buildings)
	TerrainPainter.populate(map, nodes, seed_value)
	# The selected destination has a recognizable terrain bias, without invalidating buildings.
	var preferred: TerrainType = map.catalog.by_id([&"fertile", &"dry", &"rocky"][clampi(biome, 0, 2)])
	var preferred_chance: float = 0.08 if biome == 2 else 0.22
	for cell in land:
		if occupied.has(cell) or (cell - center).length_squared() < 36: continue
		var ground: TerrainType = map.ground_at(cell)
		if ground != null and ground.kind == TerrainType.Kind.LAND and rng.randf() < preferred_chance: map.paint_tile(cell, preferred.tile, true)
	for building in buildings:
		if not building.has_meta(&"layout_kind"): building.set_meta(&"layout_kind", str(world.get_path_to(building)))
	var result: LevelData = LevelLayout.capture_data(map, nodes)
	result.generated = true
	result.seed_value = seed_value
	result.difficulty = difficulty
	result.biome = biome
	result.title = TranslationServer.translate("ui.world.generated_title") % seed_value
	world.free()
	return result
