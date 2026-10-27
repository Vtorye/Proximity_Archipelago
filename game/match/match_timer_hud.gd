class_name MatchTimerHud
extends CanvasLayer
## Optional reusable timer. Its owner supplies the controller explicitly.

## Seconds left at which the label turns red.
@export var warning_seconds := 30
@export var warning_color := Color(1.0, 0.3, 0.3)
@export var normal_color := Color.WHITE
@onready var _label: Label = $TimerLabel
var _controller: MatchController

func configure(controller: MatchController) -> void:
	_disconnect_controller()
	_controller = controller
	if _controller != null:
		_controller.time_changed.connect(_on_time_changed)
		if is_node_ready():
			_on_time_changed(ceili(_controller.time_remaining))

func _ready() -> void:
	_label.text = "--:--"
	_label.add_theme_color_override("font_color", normal_color)
	if _controller != null:
		_on_time_changed(ceili(_controller.time_remaining))

func _exit_tree() -> void:
	_disconnect_controller()

func _disconnect_controller() -> void:
	if is_instance_valid(_controller) and _controller.time_changed.is_connected(_on_time_changed):
		_controller.time_changed.disconnect(_on_time_changed)
	_controller = null

func _on_time_changed(seconds_left: int) -> void:
	var seconds: int = maxi(0, seconds_left)
	_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_label.add_theme_color_override("font_color", warning_color if seconds <= warning_seconds else normal_color)
