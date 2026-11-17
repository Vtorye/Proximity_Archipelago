class_name TileSelection
extends Node2D

const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")
## Four crisp corner brackets belong to presentation, not the simulation grid.
var map: TileMapLayer
var selected := false
var cell: Vector2i
var _guided := false
@export var guidance_color := Color("#ffd46b")
@export_range(0.0, 1.0, 0.01) var guidance_fill_opacity := 0.58
var _time := 0.0

func _ready() -> void:
	z_index = 20
	AppSettings.grid_visibility_changed.connect(queue_redraw)

func select(target: Vector2i, guided := false) -> void:
	cell = target
	_guided = guided
	selected = true
	_time = 0.0
	queue_redraw()

func clear() -> void:
	selected = false
	queue_redraw()

func _process(delta: float) -> void:
	if selected: _time += delta
	if selected or AppSettings.show_grid: queue_redraw()

func _draw() -> void:
	if map == null:
		return
	if AppSettings.show_grid:
		var transform: Transform2D = map.get_global_transform_with_canvas().affine_inverse()
		var first: Vector2i = map.local_to_map(transform * get_viewport_rect().position) - Vector2i.ONE
		var last: Vector2i = map.local_to_map(transform * get_viewport_rect().end) + Vector2i(2, 2)
		var region: Rect2i = Rect2i(first, last - first).intersection(map.get_used_rect())
		for x in range(region.position.x, region.end.x + 1):
			draw_line(_corner_at(Vector2i(x, region.position.y), Vector2(-0.5, -0.5)), _corner_at(Vector2i(x, region.end.y), Vector2(-0.5, -0.5)), PRESENTATION.grid_color, PRESENTATION.grid_width)
		for y in range(region.position.y, region.end.y + 1):
			draw_line(_corner_at(Vector2i(region.position.x, y), Vector2(-0.5, -0.5)), _corner_at(Vector2i(region.end.x, y), Vector2(-0.5, -0.5)), PRESENTATION.grid_color, PRESENTATION.grid_width)
	if not selected:
		return
	var alpha: float = lerpf(PRESENTATION.selection_min_opacity, 1.0, (1.0 + sin(_time * TAU / PRESENTATION.selection_pulse_seconds)) / 2.0)
	var white := Color(1, 1, 1, alpha)
	var pixel: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.01)
	if _guided:
		var corners := PackedVector2Array()
		for offset in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			corners.append(_corner_at(cell, offset))
		draw_colored_polygon(corners, Color(guidance_color, alpha * guidance_fill_opacity))
		corners.append(corners[0])
		draw_polyline(corners, Color(0.24, 0.15, 0.04, 0.95), 4.0 * pixel)
		draw_polyline(corners, guidance_color, 2.0 * pixel)
		return
	var arm: float = minf(PRESENTATION.selection_arm_pixels * pixel, PRESENTATION.selection_max_arm)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner: Vector2 = _corner_at(cell, Vector2(x, y) * 0.5)
			draw_line(corner + Vector2(0, y * pixel), corner + Vector2(-x * arm, y * pixel), Color(0, 0, 0, alpha), pixel)
			draw_line(corner + Vector2(x * pixel, 0), corner + Vector2(x * pixel, -y * arm), Color(0, 0, 0, alpha), pixel)
			draw_line(corner, corner + Vector2(-x * arm, 0), white, pixel)
			draw_line(corner, corner + Vector2(0, -y * arm), white, pixel)

func _corner_at(target: Vector2i, offset: Vector2) -> Vector2:
	return to_local(map.to_global(map.map_to_local(target) + Vector2(map.tile_set.tile_size) * offset))
