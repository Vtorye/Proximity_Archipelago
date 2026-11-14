extends Building
class_name Canteen

## Feeding-point marker. TripPlanner and inventory reservations own all meal transactions.

func _apply_default_appearance(sprite: Sprite2D, art: ArtCatalog) -> void:
	sprite.texture = art.canteen
	sprite.modulate = Color.WHITE
