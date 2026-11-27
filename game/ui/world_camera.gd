class_name WorldCamera
extends Camera2D
signal zoom_changed(level: int)
signal panned_by_player(distance: float)
@export var settings: CameraSettings = preload("res://game/ui/default_camera.tres")
var level: int
@export var enabled_input := true
@export var bounds := Rect2(0, 0, 800, 800)
var dragging := false
var left_button_drag := true
var _focused_nest: House

func _ready() -> void:
	level = settings.clamp_level(settings.initial_level)
	zoom = Vector2.ONE * settings.zoom_at(level)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled_input:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or (left_button_drag and event.button_index == MOUSE_BUTTON_LEFT):
			dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_level(level + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			get_viewport().set_input_as_handled()

func pan(relative: Vector2) -> void:
	if relative.is_zero_approx():
		return
	clear_nest_focus()
	var before := position
	position -= relative / zoom
	_clamp()
	if not position.is_equal_approx(before):
		panned_by_player.emit(position.distance_to(before) * zoom.x)
	force_update_scroll()

func focus_nest(nest: House) -> void:
	if not is_instance_valid(nest) or not nest.is_inside_tree():
		return
	clear_nest_focus()
	_focused_nest = nest
	nest.tree_exiting.connect(clear_nest_focus, CONNECT_ONE_SHOT)
	_center_on_nest()

func clear_nest_focus() -> void:
	if is_instance_valid(_focused_nest) and _focused_nest.tree_exiting.is_connected(clear_nest_focus):
		_focused_nest.tree_exiting.disconnect(clear_nest_focus)
	_focused_nest = null

func _center_on_nest() -> void:
	global_position = _focused_nest.global_position
	_clamp()
	force_update_scroll()

func _process(delta: float) -> void:
	if not enabled_input:
		return
	if not pan_from_input(delta) and is_instance_valid(_focused_nest):
		_center_on_nest()

func pan_from_input(delta: float) -> bool:
	var direction := Input.get_vector(&"camera_left", &"camera_right", &"camera_up", &"camera_down")
	if direction.is_zero_approx():
		return false
	pan(-direction * delta * settings.pan_speed)
	return true

func set_level(value: int) -> void:
	var next := settings.clamp_level(value)
	if next == level:
		return
	level = next
	zoom = Vector2.ONE * settings.zoom_at(level)
	if is_instance_valid(_focused_nest):
		_center_on_nest()
	else:
		_clamp()
		force_update_scroll()
	zoom_changed.emit(level)

func _clamp() -> void:
	var half_view: Vector2 = get_viewport_rect().size / zoom / 2.0
	for axis in range(2):
		if bounds.size[axis] <= half_view[axis] * 2.0:
			position[axis] = bounds.get_center()[axis]
		else:
			position[axis] = clampf(position[axis], bounds.position[axis] + half_view[axis], bounds.end[axis] - half_view[axis])
