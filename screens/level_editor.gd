extends Screen
## Edits a preview of authored map data without starting a match.

var _template: World
var _prototypes: Dictionary[String, Building]
var _map: TileMapLayer
@onready var _objects: Node2D = $Objects
@onready var _camera: WorldCamera = $Camera
@onready var _selection: TileSelection = $Selection
@onready var _brush: OptionButton = %Brush
@onready var _saved: OptionButton = %SavedMaps
@onready var _starting_maps: Array[OptionButton] = [%StartingStandard, %StartingWaves]
@onready var _title: LineEdit = %MapTitle
@onready var _status: Label = %Status
var _brushes: Array[Variant] = []
var _dirty := false
var _discard_action := ""
var _drag_button := MOUSE_BUTTON_NONE
var _pending_move: Building
var _selected_source: Workplace
@onready var _source_controls: HBoxContainer = %SourceControls
@onready var _finite: Button = %Finite
@onready var _supply: SpinBox = %Supply
@onready var _generator_seed: SpinBox = %Seed
@onready var _generator_size: OptionButton = %Extent
var _active := false

func _ready() -> void:
	_template = LevelLayout.DEFAULT_WORLD.instantiate()
	(_template.map as TerrainMap).prepare_terrain()
	_prototypes = LevelLayout.editor_prototypes(_template)
	_camera.make_current()
	_configure_controls()
	_show_world(LevelLayout.DEFAULT_WORLD.instantiate())
	_refresh_saved()

func on_focus() -> void:
	_active = true

func on_blur() -> void:
	_active = false

func _exit_tree() -> void:
	if is_instance_valid(_template):
		_template.free()

func _configure_controls() -> void:
	ColonyStyle.apply($Interface/UI)


	%Back.pressed.connect(_back)
	%Back.pressed.connect(AppSettings.play_click)
	%NewMap.pressed.connect(_new_map)
	%NewMap.pressed.connect(AppSettings.play_click)
	%SaveMap.pressed.connect(_save_map)
	%SaveMap.pressed.connect(AppSettings.play_click)
	%Play.pressed.connect(_play)
	%Play.pressed.connect(AppSettings.play_click)
	%PlayWaves.pressed.connect(_play.bind(true))
	%PlayWaves.pressed.connect(AppSettings.play_click)
	%LoadMap.pressed.connect(_load_map)
	%LoadMap.pressed.connect(AppSettings.play_click)
	%GenerateSoils.pressed.connect(_generate_soils)
	%GenerateSoils.pressed.connect(AppSettings.play_click)
	%GenerateMap.pressed.connect(_generate_map)
	%GenerateMap.pressed.connect(AppSettings.play_click)
	_title.text_changed.connect(func(_value: String): _mark_dirty())
	for index in range(_starting_maps.size()):
		var choice: OptionButton = _starting_maps[index]
		choice.item_selected.connect(func(item: int): _set_starting_map(index == 1, choice, item))
	_generator_seed.value = randi_range(1, 1000000)
	for extent in [50, 80, 120, 160]:
		_generator_size.add_item("%d × %d" % [extent, extent], extent)
	_generator_size.select(1)
	_finite.pressed.connect(AppSettings.play_click)
	_finite.toggled.connect(func(enabled: bool):
		if is_instance_valid(_selected_source):
			_selected_source.finite_supply = enabled
			_finite.text = "ui.source.finite" if enabled else "ui.source.infinite"
			_supply.editable = enabled
			_mark_dirty())
	_supply.value_changed.connect(func(value: float):
		if is_instance_valid(_selected_source):
			_selected_source.remaining_supply = int(value)
			_mark_dirty())
	_brush.item_selected.connect(func(_index: int): _pending_move = null)
	_populate_brushes()

func _populate_brushes() -> void:
	_add_brush("ui.map.move_object", &"move")
	var tiles: TileSet = _template.map.tile_set
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


func _add_brush(label: String, brush: Variant) -> void:
	_brush.add_item(tr(label))
	_brushes.append(brush)

func _show_world(world: World) -> void:
	_select_source(null)
	if is_instance_valid(_map):
		_map.free()
	for child in _objects.get_children():
		child.free()
	_map = world.map
	_map.owner = null
	world.remove_child(_map)
	add_child(_map)
	var placed: Dictionary[String, Building] = LevelLayout.prototypes(world)
	for id in placed:
		var building: Building = placed[id]
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
	var levels: Array[Dictionary] = LevelStore.saved_levels()
	_fill_map_choices(_saved, levels)
	for index in range(_starting_maps.size()):
		var waves: bool = index == 1
		var label: String = tr("ui.menu.waves" if waves else "ui.map.normal_mode")
		_fill_map_choices(_starting_maps[index], levels, LevelStore.starting_level(waves), label)

func _fill_map_choices(menu: OptionButton, levels: Array[Dictionary], selected := "", mode := "") -> void:
	menu.clear()
	var starting: bool = not mode.is_empty()
	var default_title: String = tr("ui.map.default")
	menu.add_item(tr("ui.map.mode_title") % [mode, default_title] if starting else default_title)
	menu.set_item_metadata(0, "")
	for data in levels:
		var title: String = data.title
		if starting:
			title = tr("ui.map.mode_title") % [mode, title]
		elif LevelStore.BUILT_IN_LEVELS.has(data.file):
			title += " · " + tr("ui.map.bundled")
		menu.add_item(title)
		var index: int = menu.item_count - 1
		menu.set_item_metadata(index, data.file)
		if data.file == selected:
			menu.select(index)

func _set_starting_map(waves: bool, choice: OptionButton, index: int) -> void:
	var filename: String = choice.get_item_metadata(index)
	if not filename.is_empty():
		var data: Dictionary = LevelStore.load_level(filename)
		var world: World = LevelLayout.create_world(data)
		if world == null:
			_status.text = "ui.map.load_failed"
			_refresh_saved()
			return
		world.waves.enabled = waves
		var errors: Array[String] = LevelValidator.validate_world(world, str(data.title))
		if not LevelLayout.prototypes(world).values().any(func(building: Building) -> bool: return building is House):
			errors.append(tr("ui.map.starting_requires_nest"))
		world.free()
		if not errors.is_empty():
			_status.text = errors[0]
			_status.tooltip_text = "\n".join(errors)
			_refresh_saved()
			return
	var error: Error = LevelStore.set_starting_level(filename, waves)
	if error != OK:
		_status.text = tr("ui.map.save_failed") % error_string(error)
		_refresh_saved()
		return
	_status.text = "ui.map.starting_saved"
	_status.tooltip_text = ""

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
	var description := ""
	if filename.is_empty():
		_show_world(LevelLayout.DEFAULT_WORLD.instantiate())
		_title.clear()
	else:
		var data: Dictionary = LevelStore.load_level(filename)
		description = data.get("description", "")
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
	if not description.is_empty():
		_status.text = description
		_status.tooltip_text = description.replace(". ", ".\n")

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

func _play(waves := false) -> void:
	if _dirty:
		_status.text = "ui.map.save_first"
		return
	var layout: Dictionary = LevelLayout.capture(_map, _objects.get_children())
	var world: World = LevelLayout.create_world(layout)
	if world == null:
		_status.text = "ui.map.load_failed"
		return
	world.waves.enabled = waves
	var errors: Array[String] = LevelValidator.validate_world(world, tr("ui.menu.maps"))
	world.free()
	if not errors.is_empty():
		_status.text = errors[0]
		_status.tooltip_text = "\n".join(errors)
		return
	if waves: layout["wave_mode"] = true
	Router.goto(&"match", layout)

func _process(delta: float) -> void:
	if not _active or get_viewport().gui_get_focus_owner() is LineEdit or _saved.get_popup().visible or _brush.get_popup().visible:
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
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_camera.pan(event.relative)
			get_viewport().set_input_as_handled()
		else:
			_drag_button = MOUSE_BUTTON_NONE

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
		var next_type: TerrainType = (_map as TerrainMap).catalog.for_tile(brush)
		var underlying: TerrainType = (_map as TerrainMap).ground_at(cell)
		var object: Building = _object_at(cell)
		if next_type != null and ((next_type.kind == TerrainType.Kind.ROAD and underlying != null and not underlying.roads_allowed) or (object != null and not TerrainRules.supports(next_type, TerrainRules.building_kind(object)))):
			_status.text = "ui.placement.soil_restricted"
			return
		(_map as TerrainMap).paint_tile(cell, brush, true)
		TerrainPainter.grow_wet_shore(_map, cell, _objects.get_children())
		var size := Vector2(_map.tile_set.tile_size)
		_camera.bounds = _camera.bounds.merge(Rect2(_map.to_global(_map.map_to_local(cell)) - size / 2, size).grow(160.0))
		_mark_dirty()
	elif brush == &"move":
		if is_instance_valid(_pending_move):
			if _place(_pending_move, cell):
				_pending_move = null
		else:
			_pending_move = _object_at(cell)
			_select_source(_pending_move as Workplace)
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
		if data == null or not data.get_custom_data("walkable") or occupied != null or not _allows_object(building, tile):
			building.cell = previous
			_status.text = "ui.map.invalid_object_cell"
			return false
	if building.get_parent() == null:
		_objects.add_child(building, true)
	building.global_position = _map.to_global(_map.map_to_local(cell))
	_mark_dirty()
	return true

func _generate_map() -> void:
	if _dirty and _discard_action != "generate":
		_discard_action = "generate"
		_status.text = "ui.voyage.generate_confirm"
		return
	var layout: LevelData = IslandGenerator.generate_data(int(_generator_seed.value), 0, 0, _generator_size.get_selected_id())
	var generated: World = LevelLayout.instantiate_world(layout) if layout != null else null
	if generated == null:
		_status.text = "ui.map.load_failed"
		return
	_show_world(generated)
	_title.text = layout.title
	_mark_dirty()
	_discard_action = ""
	_status.text = "ui.voyage.generated"

func _generate_soils() -> void:
	var count: int = TerrainPainter.populate(_map, _objects.get_children())
	_mark_dirty()
	_status.text = tr("ui.terrain.generated") % count

func _allows_object(building: Building, cell: Vector2i) -> bool:
	return TerrainRules.supports((_map as TerrainMap).ground_at(cell), TerrainRules.building_kind(building))

func _erase(cell: Vector2i) -> void:
	var building: Building = _object_at(cell)
	if building != null:
		if building == _selected_source:
			_select_source(null)
		if _pending_move == building:
			_pending_move = null
		building.free()
	elif _map.get_cell_source_id(cell) != -1:
		(_map as TerrainMap).erase_terrain(cell)
	else:
		return
	_mark_dirty()

func _select_source(workplace: Workplace) -> void:
	_selected_source = workplace
	_source_controls.visible = workplace != null and workplace.recipe == null and workplace.output != null
	if not _source_controls.visible:
		return
	_finite.set_pressed_no_signal(workplace.finite_supply)
	_finite.text = "ui.source.finite" if workplace.finite_supply else "ui.source.infinite"
	_supply.set_value_no_signal(workplace.remaining_supply)
	_supply.editable = workplace.finite_supply

func _object_at(cell: Vector2i, ignored: Building = null) -> Building:
	for node in _objects.get_children():
		var building: Building = node as Building
		if building != ignored and building.footprint().has(cell):
			return building
	return null
