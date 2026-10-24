class_name SceneBuildOption
extends BuildOption

@export var scene: PackedScene
## Offsets relative to the selected cell. Include the origin.
@export var occupied_cells: Array[Vector2i] = [Vector2i.ZERO]
@export var blocks_movement: bool = true
