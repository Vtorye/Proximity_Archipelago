class_name LevelLayout
extends RefCounted
## Map files describe cells and refer to authored objects by name.
const DEFAULT_WORLD := preload("res://game/worlds/world_1.tscn")
const VERSION := 1
const CELL_LIMIT := 32768
const TILE_LIMIT := 262144

static func prototypes(world: World) -> Dictionary[String, Building]:
	var buildings: Array[Building] = []
	world._collect_buildings(world, buildings)
	var result: Dictionary[String, Building] = {}
	for building in buildings:
		result[str(world.get_path_to(building))] = building
	return result

static func capture(map: TileMapLayer, buildings: Array[Node]) -> Dictionary:
	var tiles: Array = []
	for cell in map.get_used_cells():
		var atlas: Vector2i = map.get_cell_atlas_coords(cell)
		tiles.append([cell.x, cell.y, map.get_cell_source_id(cell), atlas.x, atlas.y, map.get_cell_alternative_tile(cell)])
	var objects: Array = []
	for node in buildings:
		var building: Building = node as Building
		var cell: Vector2i = map.local_to_map(map.to_local(building.global_position))
		objects.append([cell.x, cell.y, building.get_meta(&"layout_kind")])
	return {"version": VERSION, "tiles": tiles, "objects": objects}

static func create_world(layout: Dictionary) -> World:
	if layout.get("version") != VERSION or not layout.get("tiles") is Array or not layout.get("objects") is Array:
		return null
	if layout.tiles.size() > TILE_LIMIT or layout.objects.size() > layout.tiles.size():
		return null
	var world: World = DEFAULT_WORLD.instantiate()
	var map: TileMapLayer = world.get_node("Map")
	map.clear()
	if not _restore_tiles(map, layout.tiles) or not _restore_objects(world, map, layout.objects):
		world.free()
		return null
	return world

static func supports_cell(cell: Vector2i) -> bool:
	return cell.x >= -CELL_LIMIT and cell.y >= -CELL_LIMIT and cell.x < CELL_LIMIT and cell.y < CELL_LIMIT

static func _restore_tiles(map: TileMapLayer, tiles: Array) -> bool:
	for row in tiles:
		if not row is Array or row.size() != 6 or not _integers(row, 6):
			return false
		var cell := Vector2i(int(row[0]), int(row[1]))
		var source_id: int = int(row[2])
		var atlas := Vector2i(int(row[3]), int(row[4]))
		var alternative: int = int(row[5])
		if not supports_cell(cell) or map.get_cell_source_id(cell) != -1 or not map.tile_set.has_source(source_id):
			return false
		var source := map.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or not source.has_tile(atlas) or not source.has_alternative_tile(atlas, alternative):
			return false
		map.set_cell(cell, source_id, atlas, alternative)
	return true

static func _restore_objects(world: World, map: TileMapLayer, objects: Array) -> bool:
	var originals: Dictionary[String, Building] = prototypes(world)
	var occupied: Dictionary[Vector2i, bool] = {}
	for row in objects:
		if not row is Array or row.size() != 3 or not _integers(row, 2) or not row[2] is String or not originals.has(row[2]):
			return false
		var cell := Vector2i(int(row[0]), int(row[1]))
		if not supports_cell(cell):
			return false
		var building: Building = originals[row[2]].duplicate()
		building.cell = cell
		for tile in building.footprint():
			if not supports_cell(tile) or occupied.has(tile):
				building.free()
				return false
			occupied[tile] = true
		building.position = map.transform * map.map_to_local(cell)
		building.set_meta(&"layout_kind", row[2])
		world.add_child(building, true)
	for building in originals.values():
		building.free()
	return true

static func _integers(row: Array, count: int) -> bool:
	for index in range(count):
		var value: Variant = row[index]
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
		if float(value) != floorf(float(value)) or absf(float(value)) > 2147483647:
			return false
	return true
