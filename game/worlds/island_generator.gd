class_name IslandGenerator
extends RefCounted
## Deterministic map data, editable and saveable through the existing level editor.
static func generate(seed_value: int, difficulty := 0, biome := 0, extent := 80) -> Dictionary:
	extent = clampi(extent, 40, 160)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var center := Vector2i(extent / 2, extent / 2)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.1
	var tiles: Array = []
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
			tiles.append([x, y, 3, 1 if land.has(cell) else 3, 0, 0])
	var objects: Array = [[center.x, center.y, "build/base_nest"], [center.x, center.y + 3, "Food"]]
	var occupied: Dictionary[Vector2i, bool] = {center: true, center + Vector2i(0, 3): true}
	var kinds := ["Workplace", "Workplace2", "AppleTree"]
	# Guarantee a useful start; distant islands contain additional finite deposits.
	for offset in [Vector2i(-3, 2), Vector2i(3, 2), Vector2i(1, -3)]:
		var cell: Vector2i = center + offset
		objects.append([cell.x, cell.y, kinds[objects.size() - 2], {"finite_supply": false, "remaining_supply": 100}])
		occupied[cell] = true
	for cell in land:
		if (cell - center).length_squared() < 49 or occupied.has(cell) or rng.randf() > 0.025: continue
		var kind: String = kinds[rng.randi_range(0, 2)]
		objects.append([cell.x, cell.y, kind, {"finite_supply": true, "remaining_supply": maxi(20, 140 - difficulty * 12)}])
	var layout := {"version": LevelLayout.VERSION, "tiles": tiles, "objects": objects, "seed": seed_value, "difficulty": difficulty, "biome": biome}
	var world: World = LevelLayout.create_world(layout)
	if world == null: return {}
	var map := world.get_node("Map") as TerrainMap
	var buildings: Array[Building] = []
	world._collect_buildings(world, buildings)
	var nodes: Array[Node] = []
	nodes.assign(buildings)
	TerrainPainter.populate(map, nodes, seed_value)
	# The selected destination has a recognizable terrain bias, without invalidating buildings.
	var preferred: TerrainType = map.catalog.by_id([&"fertile", &"dry", &"rocky"][clampi(biome, 0, 2)])
	for cell in land:
		if occupied.has(cell) or (cell - center).length_squared() < 36: continue
		var ground: TerrainType = map.ground_at(cell)
		if ground != null and ground.kind == TerrainType.Kind.LAND and rng.randf() < 0.22: map.paint_tile(cell, preferred.tile, true)
	for building in buildings:
		if not building.has_meta(&"layout_kind"): building.set_meta(&"layout_kind", str(world.get_path_to(building)))
	var result: Dictionary = LevelLayout.capture(map, nodes)
	result.merge({"seed": seed_value, "difficulty": difficulty, "biome": biome, "title": "Остров %d" % seed_value})
	world.free()
	return result
