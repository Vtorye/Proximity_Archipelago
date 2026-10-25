class_name ArtCatalog
extends Resource
## Replace individual 16x16 PNGs or assign a complete catalog on a World.

@export var grass: Texture2D
@export var soil: Texture2D
@export var road: Texture2D
@export var water: Texture2D
@export var nest: Texture2D
@export var berries: Texture2D
@export var timber: Texture2D
@export var stone: Texture2D

func validate() -> Array[String]:
	var errors: Array[String] = []
	for name in ["grass", "soil", "road", "water", "nest", "berries", "timber", "stone"]:
		var texture: Texture2D = get(name) as Texture2D
		if texture == null or texture.get_size() != Vector2(16, 16):
			errors.append("%s must be a 16x16 texture" % name)
	return errors

func terrain_atlas() -> Texture2D:
	var image := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	var textures: Array[Texture2D] = [grass, soil, road, water]
	for index in range(textures.size()):
		var source: Image = textures[index].get_image()
		source.convert(Image.FORMAT_RGBA8)
		image.blit_rect(source, Rect2i(0, 0, 16, 16), Vector2i(index * 16, 0))
	return ImageTexture.create_from_image(image)
