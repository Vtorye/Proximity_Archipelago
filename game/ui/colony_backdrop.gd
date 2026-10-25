class_name ColonyBackdrop
extends Control
## Decorative pixel diorama, independent of simulation and its mutable state.
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
	var center: Vector2 = size * Vector2(0.68, 0.51)
	var origin: Vector2 = center - Vector2(9, 7) * tile
	for y in range(14):
		for x in range(18):
			var delta: Vector2 = Vector2(x - 8.5, y - 6.5) / Vector2(8.0, 5.5)
			var land: bool = delta.length_squared() < 0.95 + sin(x * 1.4 + y) * 0.1
			var texture: Texture2D = art.grass if land else art.water
			if land and (y == 7 or (x == 9 and y > 3)):
				texture = art.road
			draw_texture_rect(texture, Rect2(origin + Vector2(x, y) * tile, Vector2.ONE * tile), false, Color(0.8, 0.85, 0.75))
	for item in [[Vector2(8, 8), art.nest], [Vector2(5, 4), art.berries], [Vector2(12, 5), art.timber], [Vector2(12, 9), art.stone], [Vector2(5, 9), art.berries]]:
		draw_texture_rect(item[1], Rect2(origin + item[0] * tile, Vector2.ONE * tile * 1.5), false)
	for index in range(9):
		var t: float = fmod(_time * 0.04 + index / 9.0, 1.0)
		var position: Vector2 = origin + Vector2(5.0 + t * 8.0, 7.5) * tile
		draw_rect(Rect2(position, Vector2(5, 3)), Color("231c16"))
		draw_rect(Rect2(position + Vector2(5, 0), Vector2(2, 3)), Color("3f2b1c"))
