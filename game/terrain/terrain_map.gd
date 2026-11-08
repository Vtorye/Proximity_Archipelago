@tool
class_name TerrainMap
extends TileMapLayer
## Surface tiles remain compatible with old maps. Only road-covered ground needs an underlay entry.
@export var catalog: TerrainCatalog = preload("res://game/terrain/catalog.tres")
@export var underlays: Dictionary[Vector2i, Vector4i] = {}
var _prepared := false
var _editor_snapshot: Dictionary[Vector2i, Vector4i] = {}
var _tracking := false

func _enter_tree() -> void:
	prepare_terrain()
	if Engine.is_editor_hint():
		_snapshot()
		if not changed.is_connected(_queue_track): changed.connect(_queue_track)

func prepare_terrain() -> void:
	if _prepared or tile_set == null or catalog == null: return
	tile_set = tile_set.duplicate(true)
	_sync_catalog()
	if not catalog.changed.is_connected(_sync_catalog): catalog.changed.connect(_sync_catalog)
	_prepared = true

func _sync_catalog() -> void:
	catalog.install(tile_set)
	for type in catalog.types:
		if type != null and not type.changed.is_connected(_sync_catalog): type.changed.connect(_sync_catalog)

func key_at(cell: Vector2i) -> Vector4i:
	var coords: Vector2i = get_cell_atlas_coords(cell)
	return Vector4i(get_cell_source_id(cell), coords.x, coords.y, get_cell_alternative_tile(cell))

func surface_at(cell: Vector2i) -> TerrainType:
	return catalog.for_tile(key_at(cell))

func ground_at(cell: Vector2i) -> TerrainType:
	var surface: TerrainType = surface_at(cell)
	if surface != null and surface.kind == TerrainType.Kind.ROAD:
		return catalog.for_tile(underlays[cell]) if underlays.has(cell) else catalog.default_ground
	return surface

func result_key(cell: Vector2i, key: Vector4i, authoring := false) -> Vector4i:
	var target: TerrainType = catalog.for_tile(key)
	var ground: TerrainType = ground_at(cell)
	if not authoring and target != null and target.restores_ground and ground != null:
		if underlays.has(cell): return underlays[cell]
		# Soil cannot be paved over to bypass its restrictions or prices.
		if ground.preserve_ground: return ground.tile
	return key

func paint_tile(cell: Vector2i, key: Vector4i, authoring := false) -> void:
	var previous: Vector4i = key_at(cell)
	var surface: TerrainType = catalog.for_tile(previous)
	var target: TerrainType = catalog.for_tile(key)
	var final_key: Vector4i = result_key(cell, key, authoring)
	if target != null and target.kind == TerrainType.Kind.ROAD:
		if surface != null and surface.kind == TerrainType.Kind.LAND: underlays[cell] = previous
	else:
		underlays.erase(cell)
	set_cell(cell, final_key.x, Vector2i(final_key.y, final_key.z), final_key.w)

func erase_terrain(cell: Vector2i) -> void:
	underlays.erase(cell)
	erase_cell(cell)

func _snapshot() -> void:
	_editor_snapshot.clear()
	for cell in get_used_cells(): _editor_snapshot[cell] = key_at(cell)

func _queue_track() -> void:
	if _tracking: return
	_tracking = true
	_track_editor_paint.call_deferred()

func _track_editor_paint() -> void:
	_tracking = false
	for cell in get_used_cells():
		var key: Vector4i = key_at(cell)
		if _editor_snapshot.get(cell, Vector4i(-1, 0, 0, 0)) == key: continue
		var before: TerrainType = catalog.for_tile(_editor_snapshot.get(cell, Vector4i(-1, 0, 0, 0)))
		var after: TerrainType = catalog.for_tile(key)
		if after != null and after.kind == TerrainType.Kind.ROAD:
			if before != null and before.kind == TerrainType.Kind.LAND: underlays[cell] = before.tile
		else: underlays.erase(cell)
	for cell in underlays.keys():
		if get_cell_source_id(cell) < 0: underlays.erase(cell)
	_snapshot()
