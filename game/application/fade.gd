class_name Fade
extends CanvasLayer

@export var out_duration: float = 0.20
@export var in_duration: float  = 0.25

@onready var _rect: ColorRect = $ColorRect

func _ready() -> void:
	# Start opaque, the very first goto will fade in from black
	_rect.modulate.a = 1.0
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP

## Fade the screen to black
func fade_out() -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_rect, "modulate:a", 1.0, out_duration)
	await tw.finished

## Fade the screen to visible
func fade_in() -> void:
	var tw := create_tween()
	tw.tween_property(_rect, "modulate:a", 0.0, in_duration)
	await tw.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
