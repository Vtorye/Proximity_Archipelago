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
			draw_line(_corner_at(Vector2i(x, region.position.y), Vector2(-0.5, -0.5)), _corner_at(Vector2i(x, region.end.y), Vector2(-0.5, -0.5)), Color(1, 1, 1, 0.1), 0.3)
		for y in range(region.position.y, region.end.y + 1):
			draw_line(_corner_at(Vector2i(region.position.x, y), Vector2(-0.5, -0.5)), _corner_at(Vector2i(region.end.x, y), Vector2(-0.5, -0.5)), Color(1, 1, 1, 0.1), 0.3)
	if not selected:
		return
	var alpha: float = 1.0 if AppSettings.reduced_motion else 0.65 + 0.35 * sin(_time * TAU / 1.2)
	var white := Color(1, 1, 1, alpha)
	var pixel: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.01)
	var arm: float = minf(3.0 * pixel, 7.0)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner: Vector2 = _corner_at(cell, Vector2(x, y) * 0.5)
			draw_line(corner + Vector2(0, y * pixel), corner + Vector2(-x * arm, y * pixel), Color(0, 0, 0, alpha), pixel)
			draw_line(corner + Vector2(x * pixel, 0), corner + Vector2(x * pixel, -y * arm), Color(0, 0, 0, alpha), pixel)
			draw_line(corner, corner + Vector2(-x * arm, 0), white, pixel)
			draw_line(corner, corner + Vector2(0, -y * arm), white, pixel)

func _corner_at(target: Vector2i, offset: Vector2) -> Vector2:
	return to_local(map.to_global(map.map_to_local(target) + Vector2(map.tile_set.tile_size) * offset))
