class_name MatchTimerHud
extends CanvasLayer
## Match timer HUD. Drag match_timer_hud.tscn into any scene that contains a MatchController.
## Finds the controller through the MatchController.GROUP group and shows mm:ss in the top-right corner.

## Seconds left at which the label turns red.
@export var warning_seconds: int = 30
@export var warning_color: Color = Color(1.0, 0.3, 0.3)
@export var normal_color: Color = Color.WHITE

@onready var _label: Label = $TimerLabel
var _controller: MatchController


func _ready() -> void:
	_label.text = "--:--"
	_label.add_theme_color_override("font_color", normal_color)


func _process(_delta: float) -> void:
	# The controller may register in its group after this node is ready, so keep looking until found.
	if not is_instance_valid(_controller):
		_connect_controller()


func _exit_tree() -> void:
	_disconnect_controller()


func _connect_controller() -> void:
	var found := get_tree().get_first_node_in_group(MatchController.GROUP) as MatchController
	if found == null:
		return
	_controller = found
	if not _controller.time_changed.is_connected(_on_time_changed):
		_controller.time_changed.connect(_on_time_changed)
	# time_changed may have fired before we connected: show the current value right away.
	_on_time_changed(ceili(_controller.time_remaining))


func _disconnect_controller() -> void:
	if is_instance_valid(_controller) and _controller.time_changed.is_connected(_on_time_changed):
		_controller.time_changed.disconnect(_on_time_changed)
	_controller = null


func _on_time_changed(seconds_left: int) -> void:
	var seconds := maxi(0, seconds_left)
	_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_label.add_theme_color_override("font_color", warning_color if seconds <= warning_seconds else normal_color)
