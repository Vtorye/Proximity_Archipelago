class_name SceneBuildOption
extends BuildOption

@export var scene: PackedScene
## Offsets relative to the selected cell. Include the origin.
@export var occupied_cells: Array[Vector2i] = [Vector2i.ZERO]
@export var blocks_movement: bool = true
## Requires water under the footprint and a reachable entrance on land.
@export var requires_water := false
## Interaction cells are outside the blocking footprint.
@export var entry_offsets: Array[Vector2i] = [Vector2i(0, 1)]

## Population and its travel profile belong to the building definition.
@export_range(0, 100) var spawn_count := 0
@export_range(1, 128) var spawn_speed := 24.0


func entries_at(cell: Vector2i) -> Array[Vector2i]:
	if not blocks_movement and not requires_water:
		return [cell]
	var entries: Array[Vector2i] = []
	for offset in entry_offsets:
		entries.append(cell + offset)
	return entries
