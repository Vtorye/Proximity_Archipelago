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

## Catalog brushes are owned by the editor template and saved by stable build IDs.
static func editor_prototypes(world: World) -> Dictionary[String, Building]:
	var result: Dictionary[String, Building] = prototypes(world)
	for building in result.values():
		if building is House:
			building.is_main_nest = false
			building.option = load("res://game/building/options/house.tres")
	for option in world.build_catalog.options:
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
	var tiles: Array = []
	for cell in map.get_used_cells():
		var atlas: Vector2i = map.get_cell_atlas_coords(cell)
		tiles.append([cell.x, cell.y, map.get_cell_source_id(cell), atlas.x, atlas.y, map.get_cell_alternative_tile(cell)])
	var objects: Array = []
	for node in buildings:
		var building: Building = node as Building
		var cell: Vector2i = map.local_to_map(map.to_local(building.global_position))
		var kind: String = building.get_meta(&"layout_kind")
		if building is House and building.is_main_nest:
			kind = "build/base_nest"
		var row: Array = [cell.x, cell.y, kind]
		if building is Workplace:
			row.append({"finite_supply": building.finite_supply, "remaining_supply": building.remaining_supply})
			if building.improvement != null:
				row[3]["improvement"] = str(building.improvement.id)
		objects.append(row)
	var layout := {"version": VERSION, "tiles": tiles, "objects": objects}
	if map is TerrainMap and not map.underlays.is_empty():
		var underlays: Array = []
		for cell in map.underlays:
			var key: Vector4i = map.underlays[cell]
			underlays.append([cell.x, cell.y, key.x, key.y, key.z, key.w])
		layout["underlays"] = underlays
	return layout

static func create_world(layout: Dictionary) -> World:
	if layout.get("version") != VERSION or not layout.get("tiles") is Array or not layout.get("objects") is Array:
		return null
	if layout.tiles.size() > TILE_LIMIT or layout.objects.size() > layout.tiles.size():
		return null
	var world: World = DEFAULT_WORLD.instantiate()
	var map: TileMapLayer = world.get_node("Map")
	if map is TerrainMap:
		map.prepare_terrain()
		map.underlays.clear()
	map.clear()
	if not _restore_tiles(map, layout.tiles) or not _restore_underlays(map, layout.get("underlays", [])) or not _restore_objects(world, map, layout.objects):
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

static func _restore_underlays(map: TileMapLayer, rows: Variant) -> bool:
	if not rows is Array or rows.size() > map.get_used_cells().size(): return false
	if rows.is_empty(): return true
	if not map is TerrainMap: return false
	for row in rows:
		if not row is Array or row.size() != 6 or not _integers(row, 6): return false
		var cell := Vector2i(int(row[0]), int(row[1]))
		var key := Vector4i(int(row[2]), int(row[3]), int(row[4]), int(row[5]))
		var type: TerrainType = map.catalog.for_tile(key)
		var surface: TerrainType = map.surface_at(cell)
		if map.underlays.has(cell) or surface == null or surface.kind != TerrainType.Kind.ROAD or type == null or type.kind != TerrainType.Kind.LAND or not type.roads_allowed: return false
		map.underlays[cell] = key
	return true

static func _restore_objects(world: World, map: TileMapLayer, objects: Array) -> bool:
	var originals: Dictionary[String, Building] = prototypes(world)
	var catalog: Dictionary[String, SceneBuildOption] = {}
	var improvements: Dictionary[String, WorkplaceUpgradeOption] = {}
	if world.task_deck != null:
		for stage in world.task_deck.stages:
			if stage == null: continue
			for task in stage.tasks:
				if task == null: continue
				for option in task.unlocks:
					if option is WorkplaceUpgradeOption:
						improvements[str(option.id)] = option
	for option in world.build_catalog.options:
		if option is SceneBuildOption:
			catalog["build/" + str(option.id)] = option
	var occupied: Dictionary[Vector2i, bool] = {}
	for row in objects:
		if not row is Array or row.size() not in [3, 4] or not _integers(row, 2) or not row[2] is String or (not originals.has(row[2]) and not catalog.has(row[2])):
			return false
		var cell := Vector2i(int(row[0]), int(row[1]))
		if not supports_cell(cell):
			return false
		var building: Building
		if catalog.has(row[2]):
			if catalog[row[2]].scene == null:
				return false
			var instance: Node = catalog[row[2]].scene.instantiate()
			if not instance is Building:
				instance.free()
				return false
			building = instance as Building
			building.option = catalog[row[2]]
		else:
			building = originals[row[2]].duplicate()
			# Legacy Home rows mean a starter nest followed by small local nests.
			if building is House:
				building.is_main_nest = false
				building.option = load("res://game/building/options/house.tres")
		if row.size() == 4:
			if not building is Workplace or not _restore_supply(building, row[3]):
				building.free()
				return false
			if row[3].has("improvement"):
				var id: Variant = row[3].improvement
				if not id is String or not improvements.has(id) or not building.matches_improvement(improvements[id]):
					building.free()
					return false
				building.improvement = improvements[id]
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

static func _restore_supply(workplace: Workplace, data: Variant) -> bool:
	if not data is Dictionary or data.size() not in [2, 3] or not data.get("finite_supply") is bool:
		return false
	if data.size() == 3 and not data.has("improvement"):
		return false
	var amount: Variant = data.get("remaining_supply")
	if not (amount is int or amount is float) or not is_finite(float(amount)) or amount != floorf(float(amount)) or amount < 0 or amount > 1000000:
		return false
	workplace.finite_supply = data.finite_supply
	workplace.remaining_supply = int(amount)
	return true

static func _integers(row: Array, count: int) -> bool:
	for index in range(count):
		var value: Variant = row[index]
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
		if float(value) != floorf(float(value)) or absf(float(value)) > 2147483647:
			return false
	return true
