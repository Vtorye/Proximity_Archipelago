class_name NestDefaults
extends Resource
## Starting storage and stock orders for nests. Edit nest_defaults.tres to change them.
## Orders apply to every resource type; the currency (royal) is never ordered.

const PATH := "res://game/colony/nests/nest_defaults.tres"

## Storage capacity of a base (main) nest, in goods. Barracks use House.storage_capacity.
@export_range(1, 100000) var base_capacity := 1200
## Largest value a min or max order (or a one-time request) can take. Independent of capacity.
@export_range(1, 1000000) var order_limit := 10000
## Starting minimum of every base nest, per resource.
@export_range(0, 100000) var base_min := 400
## Starting minimum of every barracks, per resource.
@export_range(0, 100000) var barracks_min := 0
## Share of the warehouse reserved as the default maximum for each resource.
@export_range(0.0, 1.0, 0.01) var stock_max_fraction := 1.0 / 3.0

func stock_max_for(capacity: int) -> int:
	return mini(order_limit, roundi(capacity * stock_max_fraction))

static var _defaults: NestDefaults

static func load_defaults() -> NestDefaults:
	# Keep the authored resource alive across hot stock and capacity queries.
	if _defaults == null:
		_defaults = load(PATH) as NestDefaults
	return _defaults
