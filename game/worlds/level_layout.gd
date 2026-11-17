class_name LevelLayout
extends RefCounted
## Map files describe cells and refer to authored objects by name.
## Load lazily because world components also use level layout APIs.
static var DEFAULT_WORLD: PackedScene:
	get:
		return load("res://game/worlds/world_1.tscn") as PackedScene
const VERSION := 1
const CELL_LIMIT := 32768
const TILE_LIMIT := 262144

static func prototypes(world: World) -> Dictionary[String, Building]:
	var buildings: Array[Building] = world.placed_buildings()
	var result: Dictionary[String, Building] = {}
	for building in buildings:
		result[str(world.get_path_to(building))] = building
	return result

## Catalog brushes are owned by the editor template and saved by stable build IDs.
static func editor_prototypes(world: World) -> Dictionary[String, Building]:
	var result: Dictionary[String, Building] = prototypes(world)
	for building in result.values():
		if building is House:
			building.is_main_nest = false
			building.option = load("res://game/building/options/house.tres")
	for option in world.build_controller.initial_options():
		if not option is SceneBuildOption or option.scene == null:
			continue
		var instance: Node = option.scene.instantiate()
		if not instance is Building:
			instance.free()
			continue
		var building := instance as Building
		building.option = option
		world.add_child(building, true)
		result["build/" + str(option.id)] = building
	return result

static func capture(map: TileMapLayer, buildings: Array[Node]) -> Dictionary:
	return encode(capture_data(map, buildings))

static func capture_data(map: TileMapLayer, buildings: Array[Node]) -> LevelData:
	var data := LevelData.new()
	for cell in map.get_used_cells():
		var atlas: Vector2i = map.get_cell_atlas_coords(cell)
		data.tiles[cell] = Vector4i(map.get_cell_source_id(cell), atlas.x, atlas.y, map.get_cell_alternative_tile(cell))
	for node in buildings:
		var building: Building = node as Building
		var cell: Vector2i = map.local_to_map(map.to_local(building.global_position))
		var kind: String = building.get_meta(&"layout_kind")
		if building is House and building.is_main_nest:
			kind = "build/base_nest"
		var placement := LevelData.Placement.new(cell, kind)
		if building is Workplace:
			placement.finite_supply = building.finite_supply
			placement.remaining_supply = building.remaining_supply
			if building.improvement != null:
				placement.improvement_id = building.improvement.id
		data.objects.append(placement)
	if map is TerrainMap:
		data.underlays = map.underlays.duplicate()
	return data

static func encode(data: LevelData) -> Dictionary:
	var objects: Array = []
	for placement in data.objects:
		var row: Array = [placement.cell.x, placement.cell.y, placement.kind]
		if placement.remaining_supply >= 0:
			var supply := {"finite_supply": placement.finite_supply, "remaining_supply": placement.remaining_supply}
			if placement.improvement_id != &"":
				supply["improvement"] = str(placement.improvement_id)
			row.append(supply)
		objects.append(row)
	var layout := {"version": VERSION, "tiles": _encode_tiles(data.tiles), "objects": objects}
	if not data.underlays.is_empty():
		layout["underlays"] = _encode_tiles(data.underlays)
	if not data.title.is_empty():
		layout["title"] = data.title
	if not data.description.is_empty():
		layout["description"] = data.description
	if data.generated:
		layout["seed"] = data.seed_value
		layout["difficulty"] = data.difficulty
		layout["biome"] = data.biome
	return layout

static func decode(layout: Dictionary) -> LevelData:
	var tiles: Variant = layout.get("tiles")
	var objects: Variant = layout.get("objects")
	var underlays: Variant = layout.get("underlays", [])
	if layout.get("version") != VERSION or not tiles is Array or not objects is Array or not underlays is Array:
		return null
	if tiles.size() > TILE_LIMIT or objects.size() > tiles.size() or underlays.size() > tiles.size():
		return null
	var data := LevelData.new()
	if not _decode_tiles(tiles, data.tiles) or not _decode_tiles(underlays, data.underlays):
		return null
	for row in objects:
		if not row is Array or row.size() not in [3, 4] or not _integers(row, 2) or not row[2] is String:
			return null
		var cell := Vector2i(int(row[0]), int(row[1]))
		if not supports_cell(cell):
			return null
		var placement := LevelData.Placement.new(cell, row[2])
		if row.size() == 4 and not _decode_supply(row[3], placement):
			return null
		data.objects.append(placement)
	data.title = str(layout.get("title", ""))
	data.description = str(layout.get("description", ""))
	if layout.has("seed"):
		data.generated = true
		data.seed_value = int(layout.seed) if layout.seed is int or layout.seed is float else 0
		data.difficulty = int(layout.difficulty) if layout.get("difficulty") is int or layout.get("difficulty") is float else 0
		data.biome = int(layout.biome) if layout.get("biome") is int or layout.get("biome") is float else 0
	return data

static func create_world(layout: Dictionary) -> World:
	var data: LevelData = decode(layout)
	return instantiate_world(data) if data != null else null

static func instantiate_world(data: LevelData) -> World:
	if data == null or data.tiles.size() > TILE_LIMIT or data.objects.size() > data.tiles.size():
		return null
	var world: World = DEFAULT_WORLD.instantiate()
	var map: TileMapLayer = world.map
	if map is TerrainMap:
		map.prepare_terrain()
		map.underlays.clear()
	map.clear()
	if not _restore_tiles(map, data.tiles) or not _restore_underlays(map, data.underlays) or not _restore_objects(world, map, data.objects):
		world.free()
		return null
	return world

static func supports_cell(cell: Vector2i) -> bool:
	return cell.x >= -CELL_LIMIT and cell.y >= -CELL_LIMIT and cell.x < CELL_LIMIT and cell.y < CELL_LIMIT

static func _encode_tiles(tiles: Dictionary[Vector2i, Vector4i]) -> Array:
	var rows: Array = []
	for cell in tiles:
		var key: Vector4i = tiles[cell]
		rows.append([cell.x, cell.y, key.x, key.y, key.z, key.w])
	return rows

static func _decode_tiles(rows: Array, result: Dictionary[Vector2i, Vector4i]) -> bool:
	for row in rows:
		if not row is Array or row.size() != 6 or not _integers(row, 6):
			return false
		var cell := Vector2i(int(row[0]), int(row[1]))
		if not supports_cell(cell) or result.has(cell):
			return false
		result[cell] = Vector4i(int(row[2]), int(row[3]), int(row[4]), int(row[5]))
	return true

static func _restore_tiles(map: TileMapLayer, tiles: Dictionary[Vector2i, Vector4i]) -> bool:
	for cell in tiles:
		var tile: Vector4i = tiles[cell]
		var atlas := Vector2i(tile.y, tile.z)
		if not map.tile_set.has_source(tile.x):
			return false
		var source := map.tile_set.get_source(tile.x) as TileSetAtlasSource
		if source == null or not source.has_tile(atlas) or not source.has_alternative_tile(atlas, tile.w):
			return false
		map.set_cell(cell, tile.x, atlas, tile.w)
	return true

static func _restore_underlays(map: TileMapLayer, tiles: Dictionary[Vector2i, Vector4i]) -> bool:
	if tiles.is_empty():
		return true
	if not map is TerrainMap:
		return false
	for cell in tiles:
		var key: Vector4i = tiles[cell]
		var type: TerrainType = map.catalog.for_tile(key)
		var surface: TerrainType = map.surface_at(cell)
		if surface == null or surface.kind != TerrainType.Kind.ROAD or type == null or type.kind != TerrainType.Kind.LAND or not type.roads_allowed:
			return false
		map.underlays[cell] = key
	return true

static func _restore_objects(world: World, map: TileMapLayer, objects: Array[LevelData.Placement]) -> bool:
	var originals: Dictionary[String, Building] = prototypes(world)
	var catalog: Dictionary[String, SceneBuildOption] = {}
	var improvements: Dictionary[String, WorkplaceUpgradeOption] = {}
	if world.task_deck != null:
		for stage in world.task_deck.stages:
			if stage == null: continue
			for task in stage.tasks:
				if task == null: continue
				for variant in task.variants:
					if variant != null and variant.building is SceneBuildOption:
						catalog["build/" + str(variant.building.id)] = variant.building
				for option in task.unlocks:
					if option is WorkplaceUpgradeOption:
						improvements[str(option.id)] = option
	var definitions: Array[BuildOption] = world.build_controller.initial_options()
	if world.waves.rules != null and world.waves.rules.defenses != null:
		definitions.append_array(world.waves.rules.defenses.options)
	if world.voyage_rules != null and world.voyage_rules.ship != null:
		definitions.append(world.voyage_rules.ship)
	for option in definitions:
		if option is SceneBuildOption:
			catalog["build/" + str(option.id)] = option
	var occupied: Dictionary[Vector2i, bool] = {}
	for placement in objects:
		var kind: String = placement.kind
		if not originals.has(kind) and not catalog.has(kind):
			return false
		var cell: Vector2i = placement.cell
		var building: Building
		if catalog.has(kind):
			if catalog[kind].scene == null:
				return false
			var instance: Node = catalog[kind].scene.instantiate()
			if not instance is Building:
				instance.free()
				return false
			building = instance as Building
			building.option = catalog[kind]
		else:
			building = originals[kind].duplicate()
			# Legacy Home rows mean a starter nest followed by small local nests.
			if building is House:
				building.is_main_nest = false
				building.option = load("res://game/building/options/house.tres")
		if placement.remaining_supply >= 0:
			var workplace := building as Workplace
			if workplace == null:
				building.free()
				return false
			workplace.finite_supply = placement.finite_supply
			workplace.remaining_supply = placement.remaining_supply
			if placement.improvement_id != &"":
				var improvement: WorkplaceUpgradeOption = improvements.get(str(placement.improvement_id))
				if improvement == null or not workplace.matches_improvement(improvement):
					building.free()
					return false
				workplace.improvement = improvement
		building.cell = cell
		for tile in building.footprint():
			if not supports_cell(tile) or occupied.has(tile):
				building.free()
				return false
			occupied[tile] = true
		building.position = map.transform * map.map_to_local(cell)
		building.set_meta(&"layout_kind", kind)
		world.add_child(building, true)
	for building in originals.values():
		building.free()
	return true

static func _decode_supply(data: Variant, placement: LevelData.Placement) -> bool:
	if not data is Dictionary or data.size() not in [2, 3] or not data.get("finite_supply") is bool:
		return false
	if data.size() == 3 and (not data.get("improvement") is String or data.improvement.is_empty()):
		return false
	var amount: Variant = data.get("remaining_supply")
	if not (amount is int or amount is float) or not is_finite(float(amount)) or amount != floorf(float(amount)) or amount < 0 or amount > 1000000:
		return false
	placement.finite_supply = data.finite_supply
	placement.remaining_supply = int(amount)
	placement.improvement_id = StringName(data.get("improvement", ""))
	return true

static func _integers(row: Array, count: int) -> bool:
	for index in range(count):
		var value: Variant = row[index]
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
		if float(value) != floorf(float(value)) or absf(float(value)) > 2147483647:
			return false
	return true
