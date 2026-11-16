extends Node2D
class_name Building

signal demolished(building: Building)

var cell: Vector2i
## May be null for buildings placed in the scene from the start.
@export var option: BuildOption
var _is_setup := false
var _is_demolished := false
@export var title := "ui.building.generic"

func display_title() -> String:
	return option.display_name if option != null else title


## Called once. Fills the fields and then calls _on_setup().
func setup(origin: Vector2i, build_option: BuildOption) -> bool:
	if _is_setup:
		push_error("Building %s was already set up" % name)
		return false
	if not validate_definition().is_empty():
		return false
	cell = origin
	option = build_option
	if not _on_setup():
		return false
	_is_setup = true
	return true


## Takes the building out of play immediately: calls _on_demolish(), emits demolished,
## leaves all groups and detaches from the tree. The caller must free() the node after this
## returns (a node cannot free itself while one of its methods is running).
func demolish() -> void:
	if _is_demolished:
		return
	_is_demolished = true
	_on_demolish()
	demolished.emit(self)
	for group in get_groups():
		remove_from_group(group)
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)


## Hook for subclasses. Runs once after setup() has filled the fields.
func _on_setup() -> bool:
	return true


## Hook for subclasses. Runs before the node is freed.
func _on_demolish() -> void:
	pass

func validate_definition() -> Array[String]:
	return []

func footprint() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if self is House and (self as House).is_main_nest:
		return [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i(1, 1)]
	if self is Workplace and (self as Workplace).finite_supply and (self as Workplace).remaining_supply > 200 and (self as Workplace).output != null and (self as Workplace).output.id == &"stone":
		return [cell, cell + Vector2i.RIGHT]
	if option is SceneBuildOption:
		for offset in option.occupied_cells:
			if not cells.has(cell + offset):
				cells.append(cell + offset)
	else:
		cells.append(cell)
	return cells

func entry_cells() -> Array[Vector2i]:
	if option is SceneBuildOption:
		return option.entries_at(cell)
	return [cell]

func configure_appearance(art: ArtCatalog, tile_size: float) -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	if option != null and option.icon != null:
		sprite.texture = option.icon
	else:
		_apply_default_appearance(sprite, art)
	if sprite.texture != null:
		_finalize_appearance(sprite)
	var cells := footprint()
	var min_cell := cell
	var max_cell := cell
	for occupied_cell in cells:
		min_cell.x = mini(min_cell.x, occupied_cell.x)
		min_cell.y = mini(min_cell.y, occupied_cell.y)
		max_cell.x = maxi(max_cell.x, occupied_cell.x)
		max_cell.y = maxi(max_cell.y, occupied_cell.y)
	var size := max_cell - min_cell + Vector2i.ONE
	if sprite.texture != null:
		sprite.position = Vector2((size.x - 1) * tile_size, (size.y - 1) * tile_size) * 0.5
		sprite.scale = Vector2(tile_size * size.x, tile_size * size.y) / Vector2(sprite.texture.get_width(), sprite.texture.get_height())

func _apply_default_appearance(_sprite: Sprite2D, _art: ArtCatalog) -> void:
	pass

func _finalize_appearance(_sprite: Sprite2D) -> void:
	pass
