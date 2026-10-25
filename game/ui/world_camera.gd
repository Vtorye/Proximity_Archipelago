class_name WorldCamera
extends Camera2D
signal zoom_changed(level: int)
const ZOOMS := [0.5, 1.0, 2.0, 4.0, 6.0]
var level := 2
var enabled_input := true
var bounds := Rect2(0, 0, 800, 800)
var dragging := false

func _ready() -> void:
	zoom = Vector2.ONE * ZOOMS[level]
	position_smoothing_enabled = false

func _unhandled_input(event: InputEvent) -> void:
	if not enabled_input:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_level(level + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			get_viewport().set_input_as_handled()

func pan(relative: Vector2) -> void:
	position -= relative / zoom
	_clamp()
	force_update_scroll()

func _process(delta: float) -> void:
	if not enabled_input:
		return
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not direction.is_zero_approx():
		position += direction.normalized() * delta * 100.0 / zoom.x
		position = position.round()
		_clamp()

func set_level(value: int) -> void:
	if not enabled_input:
		return
	level = clampi(value, 0, ZOOMS.size() - 1)
	zoom = Vector2.ONE * ZOOMS[level]
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
