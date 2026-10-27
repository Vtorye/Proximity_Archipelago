class_name ColonyBackdrop
extends Control
## A complete animated forest-floor scene, never a framed marketing illustration.
var art: ArtCatalog = preload("res://game/art/colony_art.tres")
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not AppSettings.reduced_motion:
		_time += delta
		queue_redraw()

func _draw() -> void:
	var tile := 32.0
	var columns: int = ceili(size.x / tile)
	var rows: int = ceili(size.y / tile)
	var road_column: int = floori(size.x / tile / 2.0)
	var road_row: int = floori(size.y / tile / 2.0)
	for y in range(rows):
		for x in range(columns):
			var point: Vector2 = Vector2(x, y) - Vector2(columns, rows) / 2.0
			var shore: bool = point.length_squared() > 130.0 + sin(x * 1.2 + y) * 8.0
			var texture: Texture2D = art.water if shore else art.grass
			if y == road_row or x == road_column:
				texture = art.road
			draw_texture_rect(texture, Rect2(Vector2(x, y) * tile, Vector2.ONE * tile), false)
	for item in [[Vector2(0.15, 0.24), art.berries], [Vector2(0.78, 0.18), art.timber], [Vector2(0.82, 0.76), art.stone], [Vector2(0.17, 0.75), art.nest], [Vector2(0.73, 0.54), art.canteen]]:
		draw_texture_rect(item[1], Rect2((size * item[0]).floor(), Vector2(32, 32)), false)
	for index in range(28):
		var position: Vector2 = ant_position(index)
		position = position.floor()
		var forward := Vector2.RIGHT if index % 2 == 0 else Vector2.DOWN
		var side := Vector2(-forward.y, forward.x)
		var phase: float = sin(_time * 16.0 + index)
		for pair in range(3):
			var origin: Vector2 = position + forward * (pair - 1) * 2.0
			for sign_value in [-1.0, 1.0]:
				var foot: Vector2 = origin + side * sign_value * 4.0 + forward * phase * sign_value
				draw_line(origin, foot.round(), Color("181512"), 1.0)
		draw_circle(position - forward * 3, 2.5, Color("38271e"))
		draw_circle(position, 1.5, Color("211b15"))
		draw_circle(position + forward * 3, 2, Color("30221a"))
		for sign_value in [-1.0, 1.0]:
			draw_line(position + forward * 4, (position + forward * 6 + side * sign_value * 2).round(), Color("181512"), 1.0)

## Road centers come from the same tile coordinates used by the background painter.
func ant_position(index: int) -> Vector2:
	var t: float = fmod(_time * 0.035 + index / 28.0, 1.0)
	var lane: float = (index % 5 - 2) * 2.0
	var center := Vector2(floorf(size.x / 32.0 / 2.0), floorf(size.y / 32.0 / 2.0)) * 32.0 + Vector2(16, 16)
	if index % 2 == 0:
		return Vector2(t * (size.x + 16) - 8, center.y + lane)
	return Vector2(center.x + lane, t * (size.y + 16) - 8)
