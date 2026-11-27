extends Node2D

@export var rise := 22.0
@export_range(0.1, 3.0, 0.05) var duration := 0.85
@export_range(0.1, 1.0, 0.05) var initial_scale := 0.65
@export var incoming_color := Color("#bcff9c")
## Keep world feedback readable when the camera is zoomed out.
@export_range(0.5, 3.0, 0.05) var minimum_canvas_scale := 1.25
@export var outgoing_color := Color("#ffcf97")

@onready var amount_label: Label = $Content/Amount
@onready var icon: TextureRect = $Content/Icon


func _process(_delta: float) -> void:
	var canvas_scale := get_global_transform_with_canvas().get_scale().x / scale.x
	$Content.scale = Vector2.ONE * maxf(1.0, minimum_canvas_scale / canvas_scale)


func play(resource: ResourceType, amount: int) -> void:
	amount_label.text = ("+" if amount > 0 else "−") + str(absi(amount))
	amount_label.add_theme_color_override("font_color", incoming_color if amount > 0 else outgoing_color)
	icon.texture = resource.icon
	icon.visible = icon.texture != null
	scale = Vector2.ONE * initial_scale

	var animation := create_tween().set_parallel()
	animation.tween_property(self, "scale", Vector2.ONE, duration * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	animation.tween_property(self, "position:y", position.y - rise, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	animation.tween_property(self, "modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.55)
	animation.chain().tween_callback(queue_free)
