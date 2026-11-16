extends Building
class_name Canteen

## Feeding-point marker. TripPlanner and inventory reservations own all meal transactions.

@export_range(1.0, 3.0, 0.05) var visual_scale := 1.7

func configure_appearance(art: ArtCatalog, tile_size: float) -> void:
	super.configure_appearance(art, tile_size)
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.scale *= visual_scale

func _apply_default_appearance(sprite: Sprite2D, art: ArtCatalog) -> void:
	sprite.texture = art.canteen
	sprite.modulate = Color.WHITE
