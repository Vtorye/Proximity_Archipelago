class_name WorldCamera
extends Camera2D
signal zoom_changed(level: int)
var level := 3
var enabled_input := true
var bounds := Rect2(0, 0, 1600, 1600)
var _dragging := false

func _ready() -> void:
	zoom = Vector2.ONE * level
	position_smoothing_enabled = false

func _unhandled_input(event: InputEvent) -> void:
	if not enabled_input:
		_dragging = false
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_level(level + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom
		_clamp()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not enabled_input:
		return
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	position += direction.normalized() * delta * 240.0 / maxf(1.0, level / 2.0)
	_clamp()

func set_level(value: int) -> void:
	level = clampi(value, 1, 6)
	zoom = Vector2.ONE * level
	_clamp()
	zoom_changed.emit(level)

func _clamp() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, bounds.end.y)
