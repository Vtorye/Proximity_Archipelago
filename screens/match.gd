extends Screen
## Owns presentation, input, and shell integration for exactly one world session.

## Manual check of the end-of-match overlay: enable in the Inspector and start the match.
@export var debug_show_result := false
var world: World
var camera: WorldCamera
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
	camera.position = Vector2(800, 800)
	world.add_child(camera)
	camera.make_current()
	selection = TileSelection.new()
	selection.map = world.get_node("Map") as TileMapLayer
	world.add_child(selection)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = MatchHud.new()
	hud.world = world
	layer.add_child(hud)
	hud.pause_requested.connect(_open_pause)
	hud.settings_requested.connect(_open_settings)
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
	if event.is_action_pressed(&"ui_cancel"):
		var top: MenuBase = Router.top_overlay()
		if top is BuildMenu:
			top.cancel_or_close()
			get_viewport().set_input_as_handled()
		elif not Router.has_overlay() and selection.selected:
			selection.clear()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _active or Router.is_navigating():
		return
	if Router.has_overlay() and not Router.top_overlay() is BuildMenu:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var map: TileMapLayer = world.get_node("Map") as TileMapLayer
		var point: Vector2 = map.get_global_transform_with_canvas().affine_inverse() * event.position
		var cell: Vector2i = map.local_to_map(point)
		if map.get_cell_source_id(cell) != -1:
			select_cell(cell)
			get_viewport().set_input_as_handled()

func select_cell(cell: Vector2i) -> void:
	selection.select(cell)
	if is_instance_valid(_build_menu) and not _build_menu.is_queued_for_deletion():
		_build_menu.context.cell = cell
		_build_menu.context.anchor = selection.screen_rect()
		_build_menu._cancel_confirmation()
		return
	var context := BuildMenuContext.new()
	context.controller = world.build_controller
	context.population = world.population
	context.art = world.art
	context.cell = cell
	context.anchor = selection.screen_rect()
	_build_menu = Router.push_overlay(&"build", context) as BuildMenu
	if _build_menu != null:
		_build_menu.action_completed.connect(hud.toast)
		_build_menu.close_requested.connect(func(_menu: MenuBase): selection.clear())

func _process(_delta: float) -> void:
	if camera == null:
		return
	camera.enabled_input = not Router.has_overlay() or Router.top_overlay() is BuildMenu
	if is_instance_valid(_build_menu) and not _build_menu.is_queued_for_deletion():
		_build_menu.context.anchor = selection.screen_rect()

func _close_build() -> void:
	selection.clear()
	if Router.top_overlay() is BuildMenu:
		Router.pop_overlay()
	_build_menu = null

func _open_pause() -> void:
	_close_build()
	if Router.push_overlay(&"pause") != null:
		PauseController.acquire(&"menu")

func _open_settings() -> void:
	_close_build()
	Router.push_overlay(&"settings")
