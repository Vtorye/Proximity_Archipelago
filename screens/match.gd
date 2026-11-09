extends Screen
## Owns presentation, input, and shell integration for exactly one world session.

## Manual check of the end-of-match overlay: enable in the Inspector and start the match.
@export var debug_show_result := false
var world: World
var camera: WorldCamera
var navigation_overlay: NavigationOverlay
var selection: TileSelection
var campaign_panel: CampaignPanel
var hud: MatchHud
var _active := false
var _pointer := Vector2(-1, -1)
var _camera_moved := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if payload is Dictionary:
		world = LevelLayout.create_world(payload)
	if world == null:
		world = LevelLayout.DEFAULT_WORLD.instantiate()
	world.waves.enabled = payload is Dictionary and payload.get("wave_mode", false)
	world.name = "World"
	world.auto_start = false
	add_child(world)
	world.match_controller.completed.connect(_on_completed)
	camera = WorldCamera.new()
	camera.name = "ColonyCamera"
	camera.bounds = world.map_bounds()
	camera.position = camera.bounds.get_center() - Vector2(0, 8)
	world.add_child(camera)
	camera.make_current()
	navigation_overlay = NavigationOverlay.new()
	navigation_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	navigation_overlay.world = world
	navigation_overlay.z_index = 19
	world.add_child(navigation_overlay)
	selection = TileSelection.new()
	selection.process_mode = Node.PROCESS_MODE_ALWAYS
	selection.map = world.get_node("Map") as TileMapLayer
	world.add_child(selection)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = MatchHud.new()
	hud.world = world
	hud.navigation = navigation_overlay
	layer.add_child(hud)
	if world.voyage != null:
		if payload is Dictionary and payload.has("journey"): world.voyage.apply(payload.journey)
	if payload is Dictionary and payload.has("snapshot"): SessionSave.apply(world, payload.snapshot)
	campaign_panel = CampaignPanel.new()
	campaign_panel.world = world
	layer.add_child(campaign_panel)
	hud.settings_requested.connect(_open_settings)
	hud.navigation_requested.connect(_toggle_navigation)
	hud.construction_requested.connect(_open_construction)
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
	if top != null:
		camera.dragging = false
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

	if top == null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		_open_construction()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _active or Router.is_navigating(): return
	var top: MenuBase = Router.top_overlay()
	if event is InputEventMouseButton and (top == null or top is PauseMenu):
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_inspect_secondary_cell(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
		if top is PauseMenu and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_inspect_building(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
	if top == null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		_open_construction()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if camera == null:
		return
	var top: MenuBase = Router.top_overlay()
	camera.enabled_input = top == null
	hud.process_mode = Node.PROCESS_MODE_ALWAYS if top is ConstructionMenu else Node.PROCESS_MODE_PAUSABLE
	hud.lock_zoom(top != null)
	if navigation_overlay.mode == 2 and _navigation_available():
		if not selection.selected or selection.cell != navigation_overlay.origin: selection.select(navigation_overlay.origin)
	elif _navigation_available() and is_instance_valid(hud.navigation_panel.inspected_building):
		var cell: Vector2i = hud.navigation_panel.inspected_building.cell
		if not selection.selected or selection.cell != cell: selection.select(cell)
	elif selection.selected: selection.clear()
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	var panel: NavigationPanel = hud.navigation_panel
	if hovered_control == null or (hovered_control != panel and not panel.is_ancestor_of(hovered_control)):
		navigation_overlay.hover_active = _navigation_available() and hovered_control == null and get_viewport_rect().has_point(_pointer)
		if navigation_overlay.hover_active or not panel.is_visible_in_tree():
			navigation_overlay.hovered = _cell_at(_pointer)


func _cell_at(point: Vector2) -> Vector2i:
	var map: TileMapLayer = world.get_node("Map")
	return map.local_to_map(map.get_global_transform_with_canvas().affine_inverse() * point)

func _inspect_building(cell: Vector2i) -> void:
	var building: Building = world.build_controller.demolition_target(cell)
	if building is House:
		hud.navigation_panel.inspect(null)
		selection.clear()
		camera.dragging = false
		if Router.push_overlay(&"nest", {"world": world, "house": building}) != null:
			PauseController.acquire(&"menu")
	else:
		hud.navigation_panel.inspect(building)

func _inspect_secondary_cell(cell: Vector2i) -> void:
	if navigation_overlay.mode == 2:
		navigation_overlay.select_origin(cell)
	_inspect_building(cell)

func _open_settings() -> void:
	selection.clear()
	if Router.push_overlay(&"pause") != null:
		PauseController.acquire(&"menu")

func _open_construction() -> void:
	selection.clear()
	var context := ConstructionContext.new()
	context.controller = world.build_controller
	context.art = world.art
	context.camera = camera
	context.obstacles = hud.build_obstacles
	var menu: ConstructionMenu = Router.push_overlay(&"construction", context) as ConstructionMenu
	if menu == null: return
	camera.dragging = false
	camera.enabled_input = false
	menu.map_inspection_requested.connect(_inspect_secondary_cell)
	hud.set_construction_mode(true)
	menu.tree_exiting.connect(func():
		if is_instance_valid(hud): hud.set_construction_mode(false)
		if is_instance_valid(camera): camera.enabled_input = true)
	PauseController.acquire(&"menu")

func _navigation_available() -> bool:
	var top: MenuBase = Router.top_overlay()
	return _active and not Router.is_navigating() and (top == null or top is ConstructionMenu or top is PauseMenu)

func _toggle_navigation() -> void:
	if not _navigation_available(): return
	navigation_overlay.cycle()
	hud.set_navigation_mode(navigation_overlay.mode)
	if Router.has_overlay(): return
	hud.toast(["Оценки скрыты", "Время входа в клетку, мс. Скорость: %.1f. Приблизьте карту для чисел." % navigation_overlay.reference_speed, "ПКМ: начало маршрута. ЛКМ и стрелки: камера. Секунды + 0.5 × занятые места. Голод проверяется отдельно."][navigation_overlay.mode])
