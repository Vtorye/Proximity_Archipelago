class_name BuildCommand
extends RefCounted
## One immutable intent. Terrain and structures occupy independent construction layers.
var cell: Vector2i
var option: BuildOption
var removed_building: Building

static func create(origin: Vector2i, definition: BuildOption) -> BuildCommand:
	var command := BuildCommand.new()
	command.cell = origin
	command.option = definition
	return command

static func remove(building: Building) -> BuildCommand:
	var command := BuildCommand.new()
	command.cell = building.cell
	command.removed_building = building
	return command

func is_removal() -> bool:
	return option == null and removed_building != null
