extends Node2D
class_name Building

signal demolished(building: Building)

var cell: Vector2i
## May be null for buildings placed in the scene from the start.
var option: BuildOption
var _is_setup := false


## Called once. Fills the fields and then calls _on_setup().
func setup(origin: Vector2i, build_option: BuildOption) -> void:
	if _is_setup:
		push_error("Building %s was already set up" % name)
		return
	_is_setup = true
	cell = origin
	option = build_option
	_on_setup()


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
