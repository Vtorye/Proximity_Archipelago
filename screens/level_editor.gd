extends Screen
## Edits a preview of authored map data without starting a match.

var _template: World
var _prototypes: Dictionary[String, Building]
var _map: TileMapLayer
var _objects: Node2D
var _camera: WorldCamera
var _selection: TileSelection
var _brush: OptionButton
var _saved: OptionButton
var _title: LineEdit
var _status: Label
var _brushes: Array[Variant] = []
var _dirty := false
var _discard_action := ""
var _drag_button := MOUSE_BUTTON_NONE
var _pending_move: Building
var _active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_template = LevelLayout.DEFAULT_WORLD.instantiate()
	_prototypes = LevelLayout.prototypes(_template)
	_objects = Node2D.new()
	add_child(_objects)
	_objects.z_index = 1
	_camera = WorldCamera.new()
	add_child(_camera)
	_camera.enabled_input = false
	_camera.make_current()
	_selection = TileSelection.new()
	add_child(_selection)
	_make_ui()
	_show_world(LevelLayout.DEFAULT_WORLD.instantiate())
	_refresh_saved()

func on_focus() -> void:
	_active = true

func on_blur() -> void:
	_active = false

func _exit_tree() -> void:
	if is_instance_valid(_template):
		_template.free()

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var ui := Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ColonyStyle.fill(ui)
	ColonyStyle.apply(ui)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", ColonyStyle.dialog_box())
	ui.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 6
	top.offset_right = -6
	top.offset_top = 6
	var rows := VBoxContainer.new()
	top.add_child(rows)
	var actions := HBoxContainer.new()
	rows.add_child(actions)
	_button(actions, "ui.common.main_menu", _back)
	_button(actions, "ui.map.new", _new_map)
	_title = LineEdit.new()
	_title.placeholder_text = "ui.map.name"
	_title.max_length = 64
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_changed.connect(func(_value: String): _mark_dirty())
	actions.add_child(_title)
	_button(actions, "ui.map.save", _save_map)
	_button(actions, "ui.menu.play", _play)
	var files := HBoxContainer.new()
	rows.add_child(files)
	_saved = OptionButton.new()
	_saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saved.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_saved.fit_to_longest_item = false
	files.add_child(_saved)
	_button(files, "ui.map.load", _load_map)
	_status = ColonyStyle.label("", 8)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(_status)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", ColonyStyle.dialog_box())
	ui.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = 6
	bottom.offset_right = -6
	bottom.offset_bottom = -6
	var tools := VBoxContainer.new()
	bottom.add_child(tools)
	_brush = OptionButton.new()
	tools.add_child(_brush)
	_brush.item_selected.connect(func(_index: int): _pending_move = null)
	_add_brush("ui.map.move_object", &"move")
	var tiles: TileSet = (_template.get_node("Map") as TileMapLayer).tile_set
	for index in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var atlas := tiles.get_source(id) as TileSetAtlasSource
		if atlas == null:
			continue
		for tile in range(atlas.get_tiles_count()):
			var coords: Vector2i = atlas.get_tile_id(tile)
			for alternative in range(atlas.get_alternative_tiles_count(coords)):
				var alt: int = atlas.get_alternative_tile_id(coords, alternative)
				var label: String = atlas.get_tile_data(coords, alt).get_custom_data("terrain_name")
				_add_brush(label, Vector4i(id, coords.x, coords.y, alt))
	var seen: Dictionary[String, bool] = {}
	for id in _prototypes:
		var building: Building = _prototypes[id]
		var label: String = building.display_title()
		if not seen.has(label):
			_add_brush(label, id)
			seen[label] = true
	tools.add_child(ColonyStyle.label("ui.map.controls", 8))

func _button(parent: Control, key: String, action: Callable) -> void:
	var button: Button = ColonyStyle.button(key)
	button.add_theme_font_override("font", ColonyStyle.SECONDARY_FONT)
	button.add_theme_font_size_override("font_size", 8)
	button.pressed.connect(action)
	parent.add_child(button)

func _add_brush(label: String, brush: Variant) -> void:
	_brush.add_item(tr(label))
	_brushes.append(brush)

func _show_world(world: World) -> void:
	if is_instance_valid(_map):
		_map.free()
	for child in _objects.get_children():
		child.free()
	_map = world.get_node("Map")
	_map.owner = null
	world.remove_child(_map)
	add_child(_map)
	for id in LevelLayout.prototypes(world):
		var building: Building = world.get_node(id)
		var position_in_map: Vector2 = _map.to_local(building.global_position)
		building.cell = _map.local_to_map(position_in_map)
		if not building.has_meta(&"layout_kind"):
			building.set_meta(&"layout_kind", id)
		building.owner = null
		for child in building.find_children("*", "", true, false):
			if child.owner == world:
				child.owner = null
		building.reparent(_objects)
		building.global_position = _map.to_global(_map.map_to_local(building.cell))
	world.free()
	_pending_move = null
	_selection.map = _map
	_selection.clear()
	var region: Rect2i = _map.get_used_rect()
	var tile_size := Vector2(_map.tile_set.tile_size)
	_camera.bounds = (_map.transform * Rect2(Vector2(region.position) * tile_size, Vector2(region.size) * tile_size)).grow(160.0)
	_camera.position = _camera.bounds.get_center()
	_camera.set_level(1)
	_dirty = false
	_discard_action = ""

func _refresh_saved() -> void:
	_saved.clear()
	_saved.add_item(tr("ui.map.default"))
	_saved.set_item_metadata(0, "")
	for data in LevelStore.saved_levels():
		_saved.add_item(data.title)
		_saved.set_item_metadata(_saved.item_count - 1, data.file)

func _mark_dirty() -> void:
	_dirty = true
	_discard_action = ""
	_status.text = "ui.map.dirty"
	_status.tooltip_text = ""

func _confirm_discard(action: String) -> bool:
	if not _dirty or _discard_action == action:
		return true
	_discard_action = action
	_status.text = "ui.map.discard"
	return false

func _back() -> void:
	if _confirm_discard("back"):
		Router.goto(&"main_menu")

func _new_map() -> void:
	if not _confirm_discard("new"):
		return
	_show_world(LevelLayout.create_world({"version": LevelLayout.VERSION, "tiles": [], "objects": []}))
	_title.clear()
	_mark_dirty()

func _load_map() -> void:
	if not _confirm_discard("load"):
		return
	var filename: String = _saved.get_selected_metadata()
	if filename.is_empty():
		_show_world(LevelLayout.DEFAULT_WORLD.instantiate())
		_title.clear()
	else:
		var data: Dictionary = LevelStore.load_level(filename)
		var world: World = LevelLayout.create_world(data)
		if world == null:
			_status.text = "ui.map.load_failed"
			return
		_show_world(world)
		_title.text = data.title
	_dirty = false
	_discard_action = ""
	_status.text = "ui.map.loaded"
	_status.tooltip_text = ""

func _save_map() -> void:
	var title: String = _title.text.strip_edges()
	if title.is_empty():
		_status.text = "ui.map.name_needed"
		_title.grab_focus()
		return
	var layout: Dictionary = LevelLayout.capture(_map, _objects.get_children())
	var error: Error = LevelStore.save_level(title, layout)
	if error != OK:
		_status.text = tr("ui.map.save_failed") % error_string(error)
		return
	_dirty = false
	_discard_action = ""
	_status.text = "ui.map.saved"
	_refresh_saved()
	var filename: String = title.sha256_text() + ".json"
	for index in range(_saved.item_count):
		if _saved.get_item_metadata(index) == filename:
			_saved.select(index)
			break

func _play() -> void:
	if _dirty:
		_status.text = "ui.map.save_first"
		return
	var layout: Dictionary = LevelLayout.capture(_map, _objects.get_children())
	var world: World = LevelLayout.create_world(layout)
	if world == null:
		_status.text = "ui.map.load_failed"
		return
	var errors: Array[String] = LevelValidator.validate_world(world, tr("ui.menu.maps"))
	world.free()
	if not errors.is_empty():
		_status.text = errors[0]
		_status.tooltip_text = "\n".join(errors)
		return
	Router.goto(&"match", layout)

func _process(delta: float) -> void:
	if not _active or get_viewport().gui_get_focus_owner() == _title or _saved.get_popup().visible or _brush.get_popup().visible:
		return
	var direction: Vector2 = WorldCamera.keyboard_direction()
	if not direction.is_zero_approx():
		_camera.pan(-direction.normalized() * delta * 100.0)

func _input(event: InputEvent) -> void:
	if not _active or _drag_button == MOUSE_BUTTON_NONE:
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == _drag_button:
		_drag_button = MOUSE_BUTTON_NONE
	elif event is InputEventMouseMotion:
		_camera.pan(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_back()
	elif event is InputEventMouseButton and event.pressed:
		var cell: Vector2i = _cell_at(event.position)
		match event.button_index:
			MOUSE_BUTTON_LEFT: _paint(cell)
			MOUSE_BUTTON_RIGHT: _erase(cell)
			MOUSE_BUTTON_MIDDLE: _drag_button = MOUSE_BUTTON_MIDDLE
			MOUSE_BUTTON_WHEEL_UP: _camera.set_level(_camera.level + 1)
			MOUSE_BUTTON_WHEEL_DOWN: _camera.set_level(_camera.level - 1)
	elif event is InputEventMouseMotion:
		var cell: Vector2i = _cell_at(event.position)
		if _selection.cell != cell or not _selection.selected:
			_selection.select(cell)
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and _brushes[_brush.selected] is Vector4i:
			_paint(cell)

func _cell_at(point: Vector2) -> Vector2i:
	return _map.local_to_map(_map.get_global_transform_with_canvas().affine_inverse() * point)

func _paint(cell: Vector2i) -> void:
	if not LevelLayout.supports_cell(cell):
		return
	var brush: Variant = _brushes[_brush.selected]
	if brush is Vector4i:
		if _map.get_cell_source_id(cell) < 0 and _map.get_used_cells().size() >= LevelLayout.TILE_LIMIT:
			return
		_map.set_cell(cell, brush.x, Vector2i(brush.y, brush.z), brush.w)
		var size := Vector2(_map.tile_set.tile_size)
		_camera.bounds = _camera.bounds.merge(Rect2(_map.to_global(_map.map_to_local(cell)) - size / 2, size).grow(160.0))
		_mark_dirty()
	elif brush == &"move":
		if is_instance_valid(_pending_move):
			if _place(_pending_move, cell):
				_pending_move = null
		else:
			_pending_move = _object_at(cell)
			if _pending_move != null:
				_status.text = "ui.map.move_target"
	else:
		var building: Building = _prototypes[brush].duplicate()
		building.set_meta(&"layout_kind", brush)
		if not _place(building, cell):
			building.free()

func _place(building: Building, cell: Vector2i) -> bool:
	var previous: Vector2i = building.cell
	building.cell = cell
	for tile in building.footprint():
		var data: TileData = _map.get_cell_tile_data(tile)
		var occupied: Building = _object_at(tile, building)
		if data == null or not data.get_custom_data("walkable") or occupied != null:
			building.cell = previous
			_status.text = "ui.map.invalid_object_cell"
			return false
	if building.get_parent() == null:
		_objects.add_child(building, true)
	building.global_position = _map.to_global(_map.map_to_local(cell))
	_mark_dirty()
	return true

func _erase(cell: Vector2i) -> void:
	var building: Building = _object_at(cell)
	if building != null:
		if _pending_move == building:
			_pending_move = null
		building.free()
	elif _map.get_cell_source_id(cell) != -1:
		_map.erase_cell(cell)
	else:
		return
	_mark_dirty()

func _object_at(cell: Vector2i, ignored: Building = null) -> Building:
	for node in _objects.get_children():
		var building: Building = node as Building
		if building != ignored and building.footprint().has(cell):
			return building
	return null
