@tool
extends Node2D

const TIMING := preload("res://game/navigation/navigation_timing.gd")
## Rasterizes the map's visual data at one texel per cell. The TileMapLayer owns all gameplay data.

const PATCH := preload("res://game/terrain/terrain_surface_patch.tscn")
# Bound texture allocations even when authored islands are far apart.
const PATCH_SIDE := 128
# The reference mountain shader can sample two mountain widths away, up to
# five cells per width. Include the remaining peak offset and linear filter.
const SAMPLE_MARGIN := 16

@export var map: TerrainMap
@onready var _water: ColorRect = $Sea/Water
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
	if not TIMING.enabled:
		_rebuild_surface()
		return
	TIMING.begin(&"terrain_surface")
	_rebuild_surface()
	TIMING.end()

func _rebuild_surface() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var samples: Dictionary[Vector2i, Color] = {}
	var tints: Dictionary[Vector2i, Color] = {}
	var regions: Dictionary[Vector2i, Rect2i] = {}
	if map.tile_set != null and map.catalog != null and map.tile_set.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		for cell in map.get_used_cells():
			var surface := map.surface_at(cell)
			if surface != null and surface.kind == TerrainType.Kind.WATER:
				_include_region(Rect2i(cell, Vector2i.ONE), regions)
				continue
			# Opaque black protects roads and unmapped atlas tiles while keeping the coast continuous.
			var blend := surface.surface_blend if surface != null and surface.kind == TerrainType.Kind.LAND else Color.BLACK
			samples[cell] = Color(blend.r, blend.g, blend.b, 1.0)
			if blend.r > 0.0 or blend.g > 0.0 or blend.b > 0.0:
				if surface.surface_tint.a > 0.0:
					tints[cell] = surface.surface_tint
				_include_region(Rect2i(cell, Vector2i.ONE).grow(1), regions)
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
		_update_patch(key, regions[key], samples, tints)

func _include_region(area: Rect2i, regions: Dictionary[Vector2i, Rect2i]) -> void:
	var first := Vector2i((Vector2(area.position) / PATCH_SIDE).floor())
	var last := Vector2i((Vector2(area.end - Vector2i.ONE) / PATCH_SIDE).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, y)
			var grid := Rect2i(key * PATCH_SIDE, Vector2i(PATCH_SIDE, PATCH_SIDE))
			var region := area.intersection(grid)
			regions[key] = regions[key].merge(region) if regions.has(key) else region

func _update_patch(key: Vector2i, bounds: Rect2i, samples: Dictionary[Vector2i, Color], tints: Dictionary[Vector2i, Color]) -> void:
	var padded := bounds.grow(SAMPLE_MARGIN)
	var image := Image.create_empty(padded.size.x, padded.size.y, false, Image.FORMAT_RGBA8)
	var tint_image := Image.create_empty(padded.size.x, padded.size.y, false, Image.FORMAT_RGBA8)
	for y in range(padded.size.y):
		for x in range(padded.size.x):
			var pixel := Vector2i(x, y)
			var cell := padded.position + pixel
			if samples.has(cell):
				image.set_pixelv(pixel, samples[cell])
			if tints.has(cell):
				tint_image.set_pixelv(pixel, tints[cell])
	var patch := _patches.get(key) as Sprite2D
	if patch == null:
		patch = PATCH.instantiate() as Sprite2D
		patch.material = patch.material.duplicate()
		add_child(patch)
		_patches[key] = patch
	patch.offset = Vector2(bounds.position)
	patch.region_enabled = true
	patch.region_rect = Rect2(Vector2.ONE * SAMPLE_MARGIN, Vector2(bounds.size))
	patch.set_instance_shader_parameter(&"patch_origin", Vector2(padded.position))
	patch.set_instance_shader_parameter(&"water_color", _water.color)
	var existing := patch.texture as ImageTexture
	var material := patch.material as ShaderMaterial
	var tint_texture := material.get_shader_parameter(&"terrain_tint") as ImageTexture
	if existing != null and Vector2i(existing.get_size()) == padded.size:
		existing.update(image)
	else:
		var texture := ImageTexture.create_from_image(image)
		patch.texture = texture
		material.set_shader_parameter(&"world_curr_col", texture)
	if tint_texture != null and Vector2i(tint_texture.get_size()) == padded.size:
		tint_texture.update(tint_image)
	else:
		material.set_shader_parameter(&"terrain_tint", ImageTexture.create_from_image(tint_image))
