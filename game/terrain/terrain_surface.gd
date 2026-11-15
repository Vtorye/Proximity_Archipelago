@tool
extends Node2D
## Rasterizes the map's visual data at one texel per cell. The TileMapLayer owns all gameplay data.

const PATCH := preload("res://game/terrain/terrain_surface_patch.tscn")
# Bound texture allocations even when authored islands are far apart.
const PATCH_SIDE := 128
# The shader samples one neighbor across the edge of each patch.
const SAMPLE_MARGIN := 1
# With zero land coverage, the red channel distinguishes painted water from empty cells.
const WATER_SAMPLE := Color(1.0, 0.0, 0.0, 0.0)

@export var map: TerrainMap
var _patches: Dictionary[Vector2i, Sprite2D] = {}
var _queued := false

func _ready() -> void:
	if map == null:
		return
	map.changed.connect(_queue_rebuild)
	map.catalog_updated.connect(_queue_rebuild)
	map.cells_updated.connect(_queue_rebuild)
	_queue_rebuild()

func _queue_rebuild() -> void:
	if _queued:
		return
	_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var samples: Dictionary[Vector2i, Color] = {}
	var regions: Dictionary[Vector2i, Rect2i] = {}
	if map.tile_set != null and map.catalog != null and map.tile_set.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		for cell in map.get_used_cells():
			var surface := map.surface_at(cell)
			if surface != null and surface.kind == TerrainType.Kind.WATER:
				samples[cell] = WATER_SAMPLE
				_include_region(Rect2i(cell, Vector2i.ONE), regions)
				continue
			# Opaque black protects roads and unmapped atlas tiles while keeping the coast continuous.
			var blend := surface.surface_blend if surface != null and surface.kind == TerrainType.Kind.LAND else Color.BLACK
			samples[cell] = Color(blend.r, blend.g, blend.b, 1.0)
			if blend.r > 0.0 or blend.g > 0.0 or blend.b > 0.0:
				_include_region(Rect2i(cell, Vector2i.ONE).grow(SAMPLE_MARGIN), regions)
	for key in _patches.keys():
		if not regions.has(key):
			_patches[key].hide()
			_patches[key].queue_free()
			_patches.erase(key)
	if regions.is_empty():
		return
	var tile_size := Vector2(map.tile_set.tile_size)
	position = map.map_to_local(Vector2i.ZERO) - tile_size * 0.5
	scale = tile_size
	for key in regions:
		_update_patch(key, regions[key].grow(SAMPLE_MARGIN), samples)

func _include_region(area: Rect2i, regions: Dictionary[Vector2i, Rect2i]) -> void:
	var first := Vector2i((Vector2(area.position) / PATCH_SIDE).floor())
	var last := Vector2i((Vector2(area.end - Vector2i.ONE) / PATCH_SIDE).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, y)
			var grid := Rect2i(key * PATCH_SIDE, Vector2i(PATCH_SIDE, PATCH_SIDE))
			var region := area.intersection(grid)
			regions[key] = regions[key].merge(region) if regions.has(key) else region

func _update_patch(key: Vector2i, bounds: Rect2i, samples: Dictionary[Vector2i, Color]) -> void:
	var image := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	for y in range(bounds.size.y):
		for x in range(bounds.size.x):
			var pixel := Vector2i(x, y)
			var cell := bounds.position + pixel
			if samples.has(cell):
				image.set_pixelv(pixel, samples[cell])
	var patch := _patches.get(key) as Sprite2D
	if patch == null:
		patch = PATCH.instantiate() as Sprite2D
		add_child(patch)
		_patches[key] = patch
	patch.offset = Vector2(bounds.position)
	var existing := patch.texture as ImageTexture
	if existing != null and Vector2i(existing.get_size()) == bounds.size:
		existing.update(image)
	else:
		patch.texture = ImageTexture.create_from_image(image)
