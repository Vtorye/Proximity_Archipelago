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

func tile_resolution() -> int:
	var pixels := 16
	for texture in [grass, soil, road, water]:
		if texture != null:
			pixels = maxi(pixels, texture.get_width())
	return pixels
