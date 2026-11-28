class_name MapPreview
extends RefCounted
## One pixel per actual terrain cell, with landmarks taken from the destination layout.

static func texture(layout: LevelData, tiles: TileSet) -> Texture2D:
	if layout == null or layout.tiles.is_empty():
		return null
	var first: Vector2i = layout.tiles.keys().front()
	var bounds := Rect2i(first, Vector2i.ONE)
	for cell in layout.tiles:
		bounds = bounds.expand(cell + Vector2i.ONE)
		bounds = bounds.expand(cell)
	var image := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGB8)
	image.fill(ColonyStyle.color(&"map_background"))
	var palette: Dictionary[Vector3i, Color] = {}
	for cell in layout.tiles:
		var tile: Vector4i = layout.tiles[cell]
		var key := Vector3i(tile.x, tile.y, tile.z)
		if not palette.has(key):
			palette[key] = _tile_color(tiles, key)
		image.set_pixelv(cell - bounds.position, palette[key])
	for object in layout.objects:
		var cell: Vector2i = object.cell - bounds.position
		if object.kind == "build/base_nest":
			image.fill_rect(Rect2i(cell - Vector2i.ONE, Vector2i(3, 3)), ColonyStyle.color(&"map_start"))
		elif object.kind == "Food" or object.kind == "AppleTree":
			image.set_pixelv(cell, ColonyStyle.color(&"map_hostile"))
		else:
			image.set_pixelv(cell, ColonyStyle.color(&"map_feature"))
	return ImageTexture.create_from_image(image)

static func _tile_color(tiles: TileSet, key: Vector3i) -> Color:
	var source := tiles.get_source(key.x) as TileSetAtlasSource
	var sample: Image = source.texture.get_image().get_region(source.get_tile_texture_region(Vector2i(key.y, key.z)))
	sample.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	return sample.get_pixel(0, 0)
