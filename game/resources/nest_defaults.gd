class_name NestDefaults
extends Resource
## Starting storage and stock orders for nests. Edit nest_defaults.tres to change them.
## Orders apply to every resource type; the currency (royal) is never ordered.

const PATH := "res://game/resources/nest_defaults.tres"

## Storage capacity of a base (main) nest, in goods. Barracks use House.storage_capacity.
@export_range(1, 100000) var base_capacity := 1200
## Largest value a min or max order (or a one-time request) can take. Independent of capacity.
@export_range(1, 1000000) var order_limit := 10000
## Starting minimum and maximum of every base nest, per resource.
@export_range(0, 100000) var base_min := 400
@export_range(0, 100000) var base_max := 1200
## Starting minimum and maximum of every barracks, per resource.
@export_range(0, 100000) var barracks_min := 0
@export_range(0, 100000) var barracks_max := 0

static func load_defaults() -> NestDefaults:
	return load(PATH) as NestDefaults
