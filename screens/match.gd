extends Screen
## Owns presentation, input, and shell integration for exactly one world session.

## Manual check of the end-of-match overlay: enable in the Inspector and start the match.
@export var debug_show_result := false
var world: World
@onready var camera: WorldCamera = $ColonyCamera
@onready var navigation_overlay: NavigationOverlay = $Navigation
@onready var selection: TileSelection = $Selection
@onready var campaign_panel: CampaignPanel = $Interface/Campaign
@onready var hud: MatchHud = $Interface/Hud
const CONSTRUCTION_PANEL := preload("res://overlays/construction_menu.tscn")
const NEST_POPUP := preload("res://overlays/nest_menu.tscn")

var nest_popup: NestMenu
var _construction: ConstructionMenu
var _section: StringName
var _active := false
var _pointer := Vector2(-1, -1)
var _camera_moved := false

func _ready() -> void:
	var waves: bool = payload is Dictionary and payload.get("wave_mode", false)
	if payload is Dictionary and payload.has("tiles"):
		world = LevelLayout.create_world(payload)
	else:
		var seed_generator := RandomNumberGenerator.new()
		seed_generator.randomize()
		var generated: LevelData = IslandGenerator.generate_data(seed_generator.randi())
		if generated != null:
			world = LevelLayout.instantiate_world(generated)
	if world == null:
		world = LevelLayout.DEFAULT_WORLD.instantiate()
	world.waves.enabled = waves
	world.name = "World"
	world.auto_start = false
	add_child(world)
	move_child(world, 0)
	world.match_controller.completed.connect(_on_completed)
	camera.bounds = world.map_bounds()
	camera.position = camera.bounds.get_center() - Vector2(0, 8)
	camera.make_current()
	navigation_overlay.configure(world)
	selection.map = world.map
	hud.configure(world, navigation_overlay)
	camera.left_button_drag = false
	if world.voyage != null:
		if payload is Dictionary and payload.has("journey"): world.voyage.apply(payload.journey)
	if payload is Dictionary and payload.has("snapshot"): SessionSave.apply(world, payload.snapshot)
	campaign_panel.configure(world)
	hud.nest_selected.connect(camera.focus_nest)
	hud.settings_requested.connect(_open_settings)
	hud.navigation_requested.connect(_toggle_navigation)
	hud.construction_requested.connect(_select_section.bind(&"build"))
	hud.order_requested.connect(_begin_royal_order)
	hud.section_requested.connect(_select_section)
	hud.construction_bounds_changed.connect(_update_construction_dock)
	hud.pause_requested.connect(PauseController.toggle_manual)
	hud.zoom_in_requested.connect(func(): camera.set_level(camera.level + 1))
	hud.zoom_out_requested.connect(func(): camera.set_level(camera.level - 1))
	camera.zoom_changed.connect(hud.set_zoom)

func on_focus() -> void:
	_active = true
	world.start()
	if payload is Dictionary and payload.has("journey"): SessionSave.write(world)
	if debug_show_result:
		_on_completed(MatchSummary.capture(true, &"target_reached", 83.0, world.inventory))

func on_blur() -> void:
	_close_nest_popup()
	_active = false
	world.stop()
	selection.clear()

func _on_completed(summary: MatchSummary) -> void:
	if not _active or Router.is_navigating():
		return
	selection.clear()
	if world.voyage != null and world.voyage.departed: return
	if Router.push_overlay(&"match_result", summary) != null:
		PauseController.acquire(&"result")

func _input(event: InputEvent) -> void:
	if not _active or Router.is_navigating():
		return
	if event is InputEventMouseMotion: _pointer = event.position
	var top: MenuBase = Router.top_overlay()
	if top != null or _building_active():
		camera.dragging = false
	if top == null and event.is_action_pressed(&"ui_cancel") and _dismiss_visible_nest_popup():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		if event.pressed:
			_camera_moved = false
		elif camera.dragging:
			camera.dragging = false
			if event.button_index == MOUSE_BUTTON_LEFT and not _camera_moved:
				_inspect_building(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and camera.dragging:
		_camera_moved = _camera_moved or not event.relative.is_zero_approx()
		camera.pan(event.relative)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N and _navigation_available():
		_toggle_navigation()
		get_viewport().set_input_as_handled()
		return
	if top == null and event is InputEventKey and event.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		get_viewport().set_input_as_handled()
		return

func _unhandled_input(event: InputEvent) -> void:
	if not _active or Router.is_navigating(): return
	var top: MenuBase = Router.top_overlay()
	if top == null and event.is_action_pressed(&"ui_cancel") and not _building_active() and not campaign_panel.visible:
		_open_settings()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (top is PauseMenu or (top == null and not _building_active())):
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_inspect_secondary_cell(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_inspect_building(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
	if top == null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		hud.construction_requested.emit()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if camera == null:
		return
	var top: MenuBase = Router.top_overlay()
	var can_use_map: bool = top == null and not campaign_panel.visible
	if is_instance_valid(_construction):
		_construction.visible = can_use_map
	camera.enabled_input = can_use_map and not _building_active()
	if is_instance_valid(nest_popup):
		nest_popup.visible = (top == null or top is PauseMenu) and not campaign_panel.visible
		$PopupLayer.layer = 8
	hud.lock_zoom(top != null)
	if navigation_overlay.mode == 2 and _navigation_available():
		if not selection.selected or selection.cell != navigation_overlay.origin: selection.select(navigation_overlay.origin)
	elif _navigation_available() and hud.navigation_panel.inspected_cell != null:
		var cell: Vector2i = hud.navigation_panel.inspected_cell
		if not selection.selected or selection.cell != cell: selection.select(cell)
	elif selection.selected: selection.clear()
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	var panel: NavigationPanel = hud.navigation_panel
	if hovered_control == null or (hovered_control != panel and not panel.is_ancestor_of(hovered_control)):
		navigation_overlay.hover_active = _navigation_available() and hovered_control == null and get_viewport_rect().has_point(_pointer)
		if navigation_overlay.hover_active or not panel.is_visible_in_tree():
			navigation_overlay.hovered = _cell_at(_pointer)


func _cell_at(point: Vector2) -> Vector2i:
	var map: TileMapLayer = world.map
	return map.local_to_map(map.get_global_transform_with_canvas().affine_inverse() * point)

func _inspect_building(cell: Vector2i) -> void:
	var building: Building = world.registry.at(cell)
	if building is House:
		hud.navigation_panel.inspect_cell(null)
		selection.clear()
		camera.dragging = false
		if Router.top_overlay() == null:
			_open_nest_popup(building)
	else:
		hud.navigation_panel.inspect_cell(cell)

func _open_nest_popup(house: House) -> void:
	camera.clear_nest_focus()
	_close_nest_popup()
	var popup: NestMenu = NEST_POPUP.instantiate()
	popup.payload = {"world": world, "house": house}
	popup.close_requested.connect(func(_menu: MenuBase): _close_nest_popup())
	nest_popup = popup
	$PopupLayer/NestPopups.add_child(popup)

func _dismiss_visible_nest_popup() -> bool:
	if not is_instance_valid(nest_popup) or not nest_popup.is_visible_in_tree():
		return false
	_close_nest_popup()
	return true

func _close_nest_popup() -> void:
	if is_instance_valid(nest_popup):
		nest_popup.hide()
		nest_popup.queue_free()
	nest_popup = null

func _inspect_secondary_cell(cell: Vector2i) -> void:
	if navigation_overlay.mode == 2:
		navigation_overlay.select_origin(cell)
	_inspect_building(cell)

func _open_settings() -> void:
	if campaign_panel.visible or Router.has_overlay():
		return
	hud.navigation_panel.inspect_cell(null)
	selection.clear()
	if Router.push_overlay(&"pause") != null:
		PauseController.acquire(&"menu")

func _select_section(section: StringName) -> void:
	if Router.has_overlay() or campaign_panel.visible:
		return
	var already_open := _section == section
	if section == &"build" and is_instance_valid(_construction):
		already_open = _section == &"build" and _construction.is_palette_open()
	_section = &"" if already_open else section
	hud.set_section(_section)
	if _section == &"build":
		if not is_instance_valid(_construction):
			_create_construction_panel()
		_construction.show_catalog()
		camera.dragging = false
		camera.enabled_input = false
		selection.clear()
	elif _section == &"tasks" and is_instance_valid(_construction):
		_construction.select_order()
		hud.set_task_selection(null)
	elif is_instance_valid(_construction):
		_construction.set_palette_visible(false)

func _create_construction_panel() -> void:
	var context := ConstructionContext.new()
	context.controller = world.build_controller
	context.art = world.art
	context.camera = camera
	context.undo_button = hud.construction_undo_button()
	context.obstacles = _construction_obstacles
	context.dismiss_map_popup = _dismiss_visible_nest_popup
	_construction = CONSTRUCTION_PANEL.instantiate()
	_construction.payload = context
	_construction.map_inspection_requested.connect(_inspect_secondary_cell)
	_construction.pan_mode_changed.connect(hud.set_task_pan_mode)
	_construction.close_requested.connect(_close_construction_panel)
	$ConstructionLayer.add_child(_construction)
	_update_construction_dock()

func _begin_royal_order(task_id: StringName, variant_id: StringName) -> void:
	var order := world.tasks.start_order(task_id, variant_id)
	if order == null:
		return
	if not is_instance_valid(_construction):
		_create_construction_panel()
	_section = &"tasks"
	hud.set_section(_section)
	_construction.select_order(order)
	hud.set_task_selection(order)
	camera.dragging = false
	camera.enabled_input = false
	selection.clear()

func _close_construction_panel(menu: MenuBase) -> void:
	if menu != _construction:
		return
	_construction.hide()
	_construction.detach_undo()
	_construction.queue_free()
	_construction = null
	hud.set_task_selection(null)
	hud.set_task_pan_mode(false)
	if _section != &"tasks":
		_section = &""
	hud.set_section(_section)

func _building_active() -> bool:
	return is_instance_valid(_construction) and _construction.visible

func _update_construction_dock() -> void:
	if is_instance_valid(_construction):
		_construction.dock_between(hud.bottom_bar_height(), hud.colony_panel_bottom())

func _construction_obstacles() -> Array[Rect2]:
	var obstacles: Array[Rect2] = hud.build_obstacles()
	if is_instance_valid(nest_popup) and nest_popup.is_visible_in_tree():
		obstacles.append(nest_popup.panel_bounds())
	return obstacles

func _navigation_available() -> bool:
	var top: MenuBase = Router.top_overlay()
	return _active and not Router.is_navigating() and (top == null or top is PauseMenu)

func _toggle_navigation() -> void:
	if not _navigation_available(): return
	navigation_overlay.cycle()
	hud.set_navigation_mode(navigation_overlay.mode)
	if Router.has_overlay(): return
	var messages: Array[String] = [
		tr("ui.nav.hidden"),
		tr("ui.nav.entry_help") % navigation_overlay.reference_speed,
		tr("ui.nav.routes_help") % world.planner.load_penalty_seconds,
	]
	hud.toast(messages[navigation_overlay.mode])
