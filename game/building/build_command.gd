class_name BuildCommand
extends RefCounted
## One immutable intent. Terrain and structures occupy independent construction layers.
var cell: Vector2i
var option: BuildOption

static func create(origin: Vector2i, definition: BuildOption) -> BuildCommand:
	var command := BuildCommand.new()
	command.cell = origin
	command.option = definition
	return command
