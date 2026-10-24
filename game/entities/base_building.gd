extends Node2D
class_name Building

signal demolished(building: Building)

var inventory: WorldInventory
var cell: Vector2i
## May be null for buildings placed in the scene from the start.
var option: BuildOption
var _is_setup := false


## Called once. Fills the fields and then calls _on_setup().
func setup(stock: WorldInventory, origin: Vector2i, build_option: BuildOption) -> void:
	if _is_setup:
		push_error("Building %s was already set up" % name)
		return
	_is_setup = true
	inventory = stock
	cell = origin
	option = build_option
	_on_setup()


## Removes the building: calls _on_demolish(), emits demolished, then frees the node.
func demolish() -> void:
	_on_demolish()
	demolished.emit(self)
	queue_free()


## Hook for subclasses. Runs once after setup() has filled the fields.
func _on_setup() -> void:
	pass


## Hook for subclasses. Runs before the node is freed.
func _on_demolish() -> void:
	pass
