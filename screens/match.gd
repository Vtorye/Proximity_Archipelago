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
var _build_menu: BuildMenu

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
	_close_build()
	if Router.push_overlay(&"match_result", summary) != null:
		PauseController.acquire(&"result")

func _input(event: InputEvent) -> void:
	if not _active or Router.is_navigating():
		return
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
	if top == null and navigation_overlay.mode == 2 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.position.y > 60 and event.position.y < get_viewport_rect().size.y - 40:
		var map: TileMapLayer = world.get_node("Map")
		var cell: Vector2i = map.local_to_map(map.get_global_transform_with_canvas().affine_inverse() * event.position)
		navigation_overlay.select_origin(cell)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE and (top == null or top is BuildMenu):
		_open_construction()
		get_viewport().set_input_as_handled()
		return
	if top is BuildMenu and event is InputEventMouseButton and event.pressed:
		var inside: bool = top.contains_point(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_LEFT and not inside:
			_close_build()
			if event.button_index == MOUSE_BUTTON_LEFT:
				for key in [&"settings"]:
					if hud.controls[key].get_global_rect().has_point(event.position):
						return
				camera.dragging = true
			get_viewport().set_input_as_handled()
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not inside:
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"ui_cancel"):
		if top is BuildMenu:
			top.cancel_or_close()
			get_viewport().set_input_as_handled()
		elif not Router.has_overlay() and selection.selected:
			selection.clear()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _active or Router.is_navigating() or Router.has_overlay():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_B, KEY_SPACE]:
		_open_construction()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var map: TileMapLayer = world.get_node("Map") as TileMapLayer
		var point: Vector2 = map.get_global_transform_with_canvas().affine_inverse() * event.position
		var cell: Vector2i = map.local_to_map(point)
		if map.get_cell_source_id(cell) != -1:
			select_cell(cell)
			get_viewport().set_input_as_handled()

func select_cell(cell: Vector2i) -> void:
	camera.dragging = false
	camera.enabled_input = false
	selection.select(cell)
	if is_instance_valid(_build_menu) and not _build_menu.is_queued_for_deletion():
		_build_menu.retarget(cell, selection.screen_rect())
		return
	var context := BuildMenuContext.new()
	context.controller = world.build_controller
	context.population = world.population
	context.art = world.art
	context.cell = cell
	context.anchor = selection.screen_rect()
	context.obstacles = hud.build_obstacles()
	_build_menu = Router.push_overlay(&"build", context) as BuildMenu
	if _build_menu != null:
		_build_menu.action_completed.connect(hud.toast)
		_build_menu.close_requested.connect(func(_menu: MenuBase): selection.clear())

func _process(_delta: float) -> void:
	if camera == null:
		return
	camera.enabled_input = not Router.has_overlay()
	hud.lock_zoom(Router.has_overlay())
	navigation_overlay.obstacles = hud.build_obstacles()
	if is_instance_valid(_build_menu) and not _build_menu.is_queued_for_deletion():
		_build_menu.context.anchor = selection.screen_rect()
		_build_menu.context.obstacles = hud.build_obstacles()

func _close_build() -> void:
	selection.clear()
	if Router.top_overlay() is BuildMenu:
		Router.pop_overlay()
	_build_menu = null
	camera.enabled_input = true

func _open_settings() -> void:
	_close_build()
	if Router.push_overlay(&"pause") != null:
		PauseController.acquire(&"menu")

func _open_construction() -> void:
	_close_build()
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
	hud.controls[&"routes"].text = ["Маршруты [N]", "Клетки: мс [N]", "От точки: с [N]"][navigation_overlay.mode]
	hud.toast(["Оценки скрыты", "Время входа в клетку, мс. Скорость муравья: 24. Приблизьте карту для чисел.", "ЛКМ: начало маршрута. Секунды + 0.5 × занятые места. Голод проверяется отдельно."][navigation_overlay.mode])
