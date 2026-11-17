class_name WorldCamera
extends Camera2D
signal zoom_changed(level: int)
signal panned_by_player(distance: float)
const MIN_LEVEL := -1
const MAX_LEVEL := 4
const ZOOMS := {-1: 0.25, 0: 0.5, 1: 1.0, 2: 2.0, 3: 4.0, 4: 6.0}
var level := 2
@export var enabled_input := true
var bounds := Rect2(0, 0, 800, 800)
var dragging := false
var left_button_drag := true
var _focused_nest: House

func _ready() -> void:
	zoom = Vector2.ONE * ZOOMS[level]
	position_smoothing_enabled = false

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
	var direction: Vector2 = keyboard_direction()
	if not direction.is_zero_approx():
		pan(-direction.normalized() * delta * 100.0)
	elif is_instance_valid(_focused_nest):
		_center_on_nest()

static func keyboard_direction() -> Vector2:
	var right: bool = Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	var left: bool = Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var down: bool = Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var up: bool = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	return Vector2(float(right) - float(left), float(down) - float(up))

func set_level(value: int) -> void:
	var next := clampi(value, MIN_LEVEL, MAX_LEVEL)
	if next == level:
		return
	level = next
	zoom = Vector2.ONE * ZOOMS[level]
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
