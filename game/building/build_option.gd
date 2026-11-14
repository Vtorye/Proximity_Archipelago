class_name BuildOption
extends Resource

enum PlacementKind { ANY, ROAD, BERRY, NEST }
@export var placement_kind: PlacementKind = PlacementKind.ANY

@export var id: StringName
## Name or translation key shown in the construction list.
@export var display_name: String
## Description or translation key shown in the construction inspector.
@export_multiline var description: String
@export var icon: Texture2D
## Empty means free. Each entry pairs a resource with its required quantity.
@export var costs: Array[ResourceAmount] = []
@export_range(0.1, 120.0, 0.1) var construction_seconds := 4.0
@export var price_rules: Array[PriceRule] = []

## Allows terrain below existing structures and placement around units.
## Replacing a building always requires an explicit demolition command.
@export var allow_when_occupied: bool = false

func has_presentation() -> bool:
	return not display_name.strip_edges().is_empty() and not description.strip_edges().is_empty()

func cost_amount(type: ResourceType) -> int:
	var total := 0
	for cost in costs:
		if cost != null and cost.type != null and type != null and cost.type.id == type.id:
			total += cost.amount
	return total
