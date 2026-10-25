class_name ArtCatalog
extends Resource
## Default art is 16x16. Image resolution is independent of the 16-unit world grid.
## Replace PNGs or assign a complete catalog on a World; no game logic changes.

@export var grass: Texture2D
@export var soil: Texture2D
@export var road: Texture2D
@export var water: Texture2D
@export var nest: Texture2D
@export var canteen: Texture2D
@export var berries: Texture2D
@export var timber: Texture2D
@export var stone: Texture2D

func validate() -> Array[String]:
	var errors: Array[String] = []
	for name in ["grass", "soil", "road", "water", "nest", "canteen", "berries", "timber", "stone"]:
		var texture: Texture2D = get(name) as Texture2D
		if texture == null or texture.get_width() <= 0 or texture.get_width() != texture.get_height():
			errors.append("%s must be a nonempty square texture" % name)
	return errors

func terrain_atlas() -> Texture2D:
	var pixels: int = tile_resolution()
	var image := Image.create(pixels * 4, pixels, false, Image.FORMAT_RGBA8)
	var textures: Array[Texture2D] = [grass, soil, road, water]
	for index in range(textures.size()):
		var source: Image = textures[index].get_image()
		source.convert(Image.FORMAT_RGBA8)
		if source.get_width() != pixels:
			source.resize(pixels, pixels, Image.INTERPOLATE_NEAREST)
		image.blit_rect(source, Rect2i(0, 0, pixels, pixels), Vector2i(index * pixels, 0))
	return ImageTexture.create_from_image(image)

func tile_resolution() -> int:
	var pixels := 16
	for texture in [grass, soil, road, water]:
		if texture != null:
			pixels = maxi(pixels, texture.get_width())
	return pixels
