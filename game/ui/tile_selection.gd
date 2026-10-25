class_name TileSelection
extends Node2D
## Four crisp corner brackets belong to presentation, not the simulation grid.
var map: TileMapLayer
var selected := false
var cell: Vector2i
var _time := 0.0

func _ready() -> void:
	z_index = 20
	AppSettings.changed.connect(queue_redraw)

func select(target: Vector2i) -> void:
	cell = target
	selected = true
	_time = 0.0
	queue_redraw()

func clear() -> void:
	selected = false
	queue_redraw()

func screen_rect() -> Rect2:
	var size: Vector2 = Vector2(map.tile_set.tile_size)
	return map.get_global_transform_with_canvas() * Rect2(map.map_to_local(cell) - size / 2.0, size)

func _process(delta: float) -> void:
	if selected:
		_time += delta
		queue_redraw()

func _draw() -> void:
	if map == null:
		return
	if AppSettings.show_grid:
		var region: Rect2i = map.get_used_rect()
		for x in range(region.position.x, region.end.x + 1):
			var a: Vector2 = to_local(map.to_global(map.map_to_local(Vector2i(x, region.position.y)))) - Vector2(8, 8)
			var b: Vector2 = a + Vector2(0, region.size.y * 16)
			draw_line(a, b, Color(1, 1, 1, 0.1), 0.3)
		for y in range(region.position.y, region.end.y + 1):
			var a: Vector2 = to_local(map.to_global(map.map_to_local(Vector2i(region.position.x, y)))) - Vector2(8, 8)
			draw_line(a, a + Vector2(region.size.x * 16, 0), Color(1, 1, 1, 0.1), 0.3)
	if not selected:
		return
	var center: Vector2 = to_local(map.to_global(map.map_to_local(cell)))
	var alpha: float = 1.0 if AppSettings.reduced_motion else 0.65 + 0.35 * sin(_time * TAU / 1.2)
	var white := Color(1, 1, 1, alpha)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner: Vector2 = center + Vector2(x, y) * 8.0
			draw_line(corner + Vector2(0, y), corner + Vector2(-x * 4, y), Color(0, 0, 0, alpha), 1.0)
			draw_line(corner + Vector2(x, 0), corner + Vector2(x, -y * 4), Color(0, 0, 0, alpha), 1.0)
			draw_line(corner, corner + Vector2(-x * 4, 0), white, 1.0)
			draw_line(corner, corner + Vector2(0, -y * 4), white, 1.0)
