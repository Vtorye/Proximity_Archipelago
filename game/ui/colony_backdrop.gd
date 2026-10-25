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
	for y in range(rows):
		for x in range(columns):
			var point: Vector2 = Vector2(x, y) - Vector2(columns, rows) / 2.0
			var shore: bool = point.length_squared() > 130.0 + sin(x * 1.2 + y) * 8.0
			var texture: Texture2D = art.water if shore else art.grass
			if not shore and (y == rows / 2 or x == columns / 2):
				texture = art.soil
			draw_texture_rect(texture, Rect2(Vector2(x, y) * tile, Vector2.ONE * tile), false)
	for item in [[Vector2(0.15, 0.24), art.berries], [Vector2(0.78, 0.18), art.timber], [Vector2(0.82, 0.76), art.stone], [Vector2(0.17, 0.75), art.nest], [Vector2(0.73, 0.54), art.canteen]]:
		draw_texture_rect(item[1], Rect2((size * item[0]).floor(), Vector2(32, 32)), false)
	for index in range(28):
		var t: float = fmod(_time * 0.035 + index / 28.0, 1.0)
		var position: Vector2
		if index % 2 == 0:
			position = Vector2(t * (size.x + 16) - 8, size.y * 0.5 + (index % 5 - 2) * 2)
		else:
			position = Vector2(size.x * 0.5 + (index % 5 - 2) * 2, t * (size.y + 16) - 8)
		position = position.floor()
		var color := Color("211c18")
		draw_rect(Rect2(position, Vector2(3, 2)), color)
		draw_rect(Rect2(position + Vector2(3, 0), Vector2(2, 2)), color)
		var phase: int = int(_time * 9.0 + index) % 2
		for leg in range(3):
			draw_rect(Rect2(position + Vector2(leg * 2, -1 - phase), Vector2(1, 1)), color)
			draw_rect(Rect2(position + Vector2(leg * 2, 2 + phase), Vector2(1, 1)), color)
