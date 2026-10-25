extends Node2D
class_name Building

signal demolished(building: Building)

var cell: Vector2i
## May be null for buildings placed in the scene from the start.
@export var option: BuildOption
var _is_setup := false


## Called once. Fills the fields and then calls _on_setup().
func setup(origin: Vector2i, build_option: BuildOption) -> bool:
	if _is_setup:
		push_error("Building %s was already set up" % name)
		return false
	if not validate_definition().is_empty():
		return false
	_is_setup = true
	cell = origin
	option = build_option
	_on_setup()
	return true


## Takes the building out of play immediately: calls _on_demolish(), emits demolished,
## leaves all groups and detaches from the tree. The caller must free() the node after this
## returns (a node cannot free itself while one of its methods is running).
func demolish() -> void:
	_on_demolish()
	demolished.emit(self)
	for group in get_groups():
		remove_from_group(group)
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)


## Hook for subclasses. Runs once after setup() has filled the fields.
func _on_setup() -> void:
	pass


## Hook for subclasses. Runs before the node is freed.
func _on_demolish() -> void:
	pass

func validate_definition() -> Array[String]:
	return []

func footprint() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if option is SceneBuildOption:
		for offset in option.occupied_cells:
			if not cells.has(cell + offset):
				cells.append(cell + offset)
	else:
		cells.append(cell)
	return cells

func entry_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if option is SceneBuildOption and option.blocks_movement:
		for offset in option.entry_offsets:
			cells.append(cell + offset)
	else:
		cells.append(cell)
	return cells
