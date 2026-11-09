class_name MapPreview
extends RefCounted
## One pixel per actual terrain cell, with landmarks taken from the destination layout.

static func texture(layout: Dictionary, tiles: TileSet) -> Texture2D:
	var cells: Array = layout.get("tiles", [])
	if cells.is_empty():
		return null
	var first: Array = cells[0]
	var bounds := Rect2i(Vector2i(first[0], first[1]), Vector2i.ONE)
	for row in cells:
		bounds = bounds.expand(Vector2i(row[0], row[1]) + Vector2i.ONE)
		bounds = bounds.expand(Vector2i(row[0], row[1]))
	var image := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGB8)
	image.fill(Color("152825"))
	var palette: Dictionary[Vector3i, Color] = {}
	for row in cells:
		var key := Vector3i(row[2], row[3], row[4])
		if not palette.has(key):
			palette[key] = _tile_color(tiles, key)
		image.set_pixelv(Vector2i(row[0], row[1]) - bounds.position, palette[key])
	for object in layout.get("objects", []):
		var cell := Vector2i(object[0], object[1]) - bounds.position
		if object[2] == "build/base_nest":
			image.fill_rect(Rect2i(cell - Vector2i.ONE, Vector2i(3, 3)), Color("f5cd87"))
		elif object[2] == "Food" or object[2] == "AppleTree":
			image.set_pixelv(cell, Color("f0a386"))
		else:
			image.set_pixelv(cell, Color("cbd6ce"))
	return ImageTexture.create_from_image(image)

static func _tile_color(tiles: TileSet, key: Vector3i) -> Color:
	var source := tiles.get_source(key.x) as TileSetAtlasSource
	var sample: Image = source.texture.get_image().get_region(source.get_tile_texture_region(Vector2i(key.y, key.z)))
	sample.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	return sample.get_pixel(0, 0)
