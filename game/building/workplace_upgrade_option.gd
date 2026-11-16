class_name WorkplaceUpgradeOption
extends BuildOption
## An extra construction layer on an existing raw resource workplace.
@export var source_type: ResourceType
@export_range(1, 100) var added_slots := 2

func valid() -> bool:
	return source_type != null and added_slots > 0 and icon != null
