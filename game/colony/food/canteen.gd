extends Building
class_name Canteen

## Feeding point supplied by carriers. WorldInventory owns its food stock.

signal food_request_changed

const USE_DEFAULT := -1

@export_range(1.0, 3.0, 0.05) var visual_scale := 1.7
@export_range(1, 1000) var food_capacity := 12
## Default refill threshold as a share of capacity, bounded by the default maximum.
@export_range(0.0, 1.0, 0.05) var refill_fraction := 0.5

var incoming_food := 0
var _minimum_override := USE_DEFAULT
var _maximum_override := USE_DEFAULT
var _requested_food := 0
var food_minimum: int:
	get:
		# Orders trigger below the minimum, matching the original inclusive threshold.
		var minimum := floori(food_capacity * refill_fraction) + 1 if _minimum_override == USE_DEFAULT else _minimum_override
		return mini(minimum, food_maximum)
var food_maximum: int:
	get:
		if _maximum_override == USE_DEFAULT:
			return NestDefaults.load_defaults().stock_max_for(food_capacity)
		return mini(_maximum_override, food_capacity)
var requested_food: int:
	get:
		return _requested_food

func food_needed(stock: int, accept_surplus := false) -> int:
	var supplied := stock + incoming_food
	var refill := food_maximum - supplied if accept_surplus or supplied < food_minimum else 0
	var requested := _requested_food - incoming_food
	return clampi(maxi(refill, requested), 0, maxi(0, food_capacity - supplied))

func set_food_order(field: String, value: int) -> void:
	var limit := clampi(value, 0, food_capacity)
	if field == "min":
		_maximum_override = maxi(food_maximum, limit)
		_minimum_override = limit
	elif field == "max":
		_minimum_override = mini(food_minimum, limit)
		_maximum_override = limit

func request_food(amount: int) -> void:
	var requested := clampi(amount, 0, WorldInventory.order_limit())
	if _requested_food != requested:
		_requested_food = requested
		food_request_changed.emit()

func fulfil_food_request(amount: int) -> void:
	request_food(_requested_food - amount)

func capture_delivery_settings() -> Dictionary:
	return {"min": _minimum_override, "max": _maximum_override, "requested": _requested_food}

func restore_delivery_settings(state: Dictionary) -> void:
	_minimum_override = clampi(int(state.get("min", USE_DEFAULT)), USE_DEFAULT, food_capacity)
	_maximum_override = clampi(int(state.get("max", USE_DEFAULT)), USE_DEFAULT, food_capacity)
	request_food(int(state.get("requested", 0)))

func configure_appearance(art: ArtCatalog, tile_size: float) -> void:
	super.configure_appearance(art, tile_size)
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.scale *= visual_scale

func _apply_default_appearance(sprite: Sprite2D, art: ArtCatalog) -> void:
	sprite.texture = art.canteen
	sprite.modulate = Color.WHITE
