extends Screen
## Owns presentation, input, and shell integration for exactly one world session.

## Manual check of the end-of-match overlay: enable in the Inspector and start the match.
@export var debug_show_result := false
var world: World
var camera: WorldCamera
var navigation_overlay: NavigationOverlay
var selection: TileSelection
var hud: MatchHud
var _active := false
var _pointer := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = $World
	world.match_controller.completed.connect(_on_completed)
	camera = WorldCamera.new()
	camera.name = "ColonyCamera"
	camera.bounds = world.map_bounds()
	camera.position = camera.bounds.get_center() - Vector2(0, 8)
	world.add_child(camera)
	camera.make_current()
	navigation_overlay = NavigationOverlay.new()
	navigation_overlay.world = world
	navigation_overlay.z_index = 19
	world.add_child(navigation_overlay)
	selection = TileSelection.new()
	selection.map = world.get_node("Map") as TileMapLayer
	world.add_child(selection)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = MatchHud.new()
	hud.world = world
	hud.navigation = navigation_overlay
	layer.add_child(hud)
	hud.settings_requested.connect(_open_settings)
	hud.navigation_requested.connect(_toggle_navigation)
	hud.construction_requested.connect(_open_construction)
	hud.zoom_in_requested.connect(func(): camera.set_level(camera.level + 1))
	hud.zoom_out_requested.connect(func(): camera.set_level(camera.level - 1))
	camera.zoom_changed.connect(hud.set_zoom)

func on_focus() -> void:
	_active = true
	world.start()
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
	if Router.push_overlay(&"match_result", summary) != null:
		PauseController.acquire(&"result")

func _input(event: InputEvent) -> void:
	if not _active or Router.is_navigating():
		return
	if event is InputEventMouseMotion: _pointer = event.position
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE] and camera.dragging:
		camera.dragging = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and camera.dragging:
		camera.pan(event.relative)
		get_viewport().set_input_as_handled()
		return
	var top: MenuBase = Router.top_overlay()
	if top == null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
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
	if not _active or Router.is_navigating() or Router.has_overlay(): return
	if navigation_overlay.mode == 2 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var map: TileMapLayer = world.get_node("Map")
		var cell: Vector2i = map.local_to_map(map.get_global_transform_with_canvas().affine_inverse() * event.position)
		navigation_overlay.select_origin(cell)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		_open_construction()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if camera == null:
		return
	camera.enabled_input = not Router.has_overlay()
	hud.lock_zoom(Router.has_overlay())
	if navigation_overlay.mode == 2 and not Router.has_overlay():
		if not selection.selected or selection.cell != navigation_overlay.origin: selection.select(navigation_overlay.origin)
	elif selection.selected: selection.clear()
	var map: TileMapLayer = world.get_node("Map")
	navigation_overlay.hovered = map.local_to_map(map.get_global_transform_with_canvas().affine_inverse() * _pointer)

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
	context.obstacles = hud.build_obstacles()
	var menu: ConstructionMenu = Router.push_overlay(&"construction", context) as ConstructionMenu
	if menu == null: return
	camera.dragging = false
	camera.enabled_input = false
	hud.set_construction_mode(true)
	menu.tree_exiting.connect(func():
		if is_instance_valid(hud): hud.set_construction_mode(false)
		if is_instance_valid(camera): camera.enabled_input = true)
	PauseController.acquire(&"menu")

func _toggle_navigation() -> void:
	navigation_overlay.cycle()
	hud.controls[&"routes"].text = ["Пути [N]", "Клетки: мс [N]", "Приоритеты [N]"][navigation_overlay.mode]
	hud.toast(["Оценки скрыты", "Время входа в клетку, мс. Скорость: %.1f. Приблизьте карту для чисел." % navigation_overlay.reference_speed, "ПКМ: начало маршрута. ЛКМ и стрелки: камера. Секунды + 0.5 × занятые места. Голод проверяется отдельно."][navigation_overlay.mode])
