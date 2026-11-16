class_name NestBuildOption
extends SceneBuildOption
## Capacity of the completed nest. Initial residents are configured separately.

@export_range(1, 1000) var resident_capacity := 5
## Holds goods in a barracks. Zero uses the shared main nest capacity from NestDefaults.
@export_range(0, 10000) var storage_capacity := 0

func stock_capacity() -> int:
	return storage_capacity if storage_capacity > 0 else NestDefaults.load_defaults().base_capacity
