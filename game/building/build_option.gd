class_name BuildOption
extends Resource

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var cost: ResourceAmount

## Allows terrain below existing structures and placement around units.
## Replacing a building always requires an explicit demolition command.
@export var allow_when_occupied: bool = false
