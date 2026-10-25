class_name UiScaleBinding
extends Node
## Scale presentation roots independently of the camera, world, and physical tile size.
var target: Control

func _ready() -> void:
	AppSettings.changed.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize()

func _resize() -> void:
	var factor: float = AppSettings.ui_scale
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	target.scale = Vector2.ONE * factor
	target.position = Vector2.ZERO
	target.size = get_viewport().get_visible_rect().size / factor
