extends Building
class_name Canteen

## Feeding point supplied by carriers. WorldInventory owns its food stock.

@export_range(1.0, 3.0, 0.05) var visual_scale := 1.7
@export_range(1, 1000) var food_capacity := 12
## Order a refill once the share of occupied storage reaches this level or lower.
@export_range(0.0, 1.0, 0.05) var refill_fraction := 0.5

var incoming_food := 0

func food_needed(stock: int) -> int:
	var supplied := stock + incoming_food
	if supplied > food_capacity * refill_fraction:
		return 0
	return maxi(0, food_capacity - supplied)

func configure_appearance(art: ArtCatalog, tile_size: float) -> void:
	super.configure_appearance(art, tile_size)
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.scale *= visual_scale

func _apply_default_appearance(sprite: Sprite2D, art: ArtCatalog) -> void:
	sprite.texture = art.canteen
	sprite.modulate = Color.WHITE
