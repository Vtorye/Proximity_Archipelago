class_name TerrainPainter
extends RefCounted
## Authoring-only biome distribution. Saved maps are never regenerated during play.
const OFFSETS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

static func populate(map: TerrainMap, objects: Array[Node], seed_value := 814) -> int:
	map.prepare_terrain()
	var distances: Dictionary[Vector2i, int] = _water_distances(map)
	var protected: Dictionary[Vector2i, int] = {}
	var stone_cells: Array[Vector2i] = []
	for object in objects:
		var building := object as Building
		if building == null: continue
		building.cell = map.local_to_map(map.to_local(building.global_position))
		for cell in building.footprint(): protected[cell] = TerrainRules.building_kind(building)
		if building is Workplace and building.output != null and building.output.id == &"stone": stone_cells.append(building.cell)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.09
	noise.fractal_octaves = 2
	var count := 0
	for cell in map.get_used_cells():
		var ground: TerrainType = map.ground_at(cell)
		if ground == null or ground.kind != TerrainType.Kind.LAND: continue
		var distance: int = distances.get(cell, 7)
		var value: float = noise.get_noise_2d(cell.x, cell.y)
		var id: StringName = &""
		if distance == 1: id = &"sand" if value > 0.1 else &"wet"
		elif distance == 2: id = &"wet"
		elif stone_cells.any(func(stone: Vector2i) -> bool: return (stone - cell).length_squared() <= 5): id = &"rocky"
		elif distance >= 5 and value > 0.08: id = &"dry"
		elif value < -0.04: id = &"fertile"
		var type: TerrainType = map.catalog.by_id(id) if id != &"" else (map.catalog.default_ground if ground.preserve_ground else ground)
		if type == null: continue
		if protected.get(cell) == BuildOption.PlacementKind.NEST and not type.nests_allowed:
			type = map.catalog.by_id(&"dry" if distance >= 4 else &"fertile")
		elif protected.get(cell) == BuildOption.PlacementKind.BERRY and not type.berries_allowed:
			type = map.catalog.by_id(&"wet")
		var surface: TerrainType = map.surface_at(cell)
		if surface.kind == TerrainType.Kind.ROAD:
			if not type.roads_allowed: type = map.catalog.default_ground
			map.underlays[cell] = type.tile
		else:
			map.paint_tile(cell, type.tile, true)
		count += 1
	return count

## Painting water grows damp ground beside it without changing already authored special soils or buildings.
static func grow_wet_shore(map: TerrainMap, water: Vector2i, objects: Array[Node]) -> void:
	var type: TerrainType = map.surface_at(water)
	if type == null or type.kind != TerrainType.Kind.WATER: return
	var occupied: Dictionary[Vector2i, bool] = {}
	for node in objects:
		if node is Building:
			for cell in node.footprint(): occupied[cell] = true
	var wet: TerrainType = map.catalog.by_id(&"wet")
	for offset in OFFSETS:
		var cell: Vector2i = water + offset
		var ground: TerrainType = map.ground_at(cell)
		if occupied.has(cell) or ground == null or ground.kind != TerrainType.Kind.LAND or ground.preserve_ground: continue
		if map.surface_at(cell).kind == TerrainType.Kind.ROAD: map.underlays[cell] = wet.tile
		else: map.paint_tile(cell, wet.tile, true)

static func _water_distances(map: TerrainMap) -> Dictionary[Vector2i, int]:
	var distances: Dictionary[Vector2i, int] = {}
	var queue: Array[Vector2i] = []
	for cell in map.get_used_cells():
		var type: TerrainType = map.surface_at(cell)
		if type == null or type.kind == TerrainType.Kind.WATER: continue
		for offset in OFFSETS:
			var neighbor: TerrainType = map.surface_at(cell + offset)
			if neighbor != null and neighbor.kind == TerrainType.Kind.WATER:
				distances[cell] = 1
				queue.append(cell)
				break
	var index := 0
	while index < queue.size():
		var cell: Vector2i = queue[index]
		index += 1
		if distances[cell] >= 6: continue
		for offset in OFFSETS:
			var next: Vector2i = cell + offset
			var type: TerrainType = map.surface_at(next)
			if distances.has(next) or type == null or type.kind == TerrainType.Kind.WATER: continue
			distances[next] = distances[cell] + 1
			queue.append(next)
	return distances
