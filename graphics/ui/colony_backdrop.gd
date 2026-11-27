class_name ColonyBackdrop
extends Control

const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")
## Animated ant traffic and skirmishes layered over the menu's shader terrain.
@export var art: ArtCatalog = preload("res://graphics/catalog/colony_art.tres")
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var tile: float = PRESENTATION.backdrop_tile_size
	var columns: int = ceili(size.x / tile)
	var rows: int = ceili(size.y / tile)
	var road_center: Vector2 = (size / tile / 2.0).floor() * tile + Vector2.ONE * tile / 2.0
	for x in range(columns):
		draw_texture_rect(art.road, Rect2(Vector2(x * tile, road_center.y - tile / 2.0), Vector2.ONE * tile), false)
	for y in range(rows):
		draw_texture_rect(art.road, Rect2(Vector2(road_center.x - tile / 2.0, y * tile), Vector2.ONE * tile), false)
	_draw_marker_grain()
	# Small resource landmarks keep the colony readable without covering the shader-rendered floor.
	for item in [[PRESENTATION.backdrop_berries_position, art.berries], [PRESENTATION.backdrop_timber_position, art.timber], [PRESENTATION.backdrop_stone_position, art.stone], [PRESENTATION.backdrop_nest_position, art.nest], [PRESENTATION.backdrop_canteen_position, art.canteen]]:
		draw_texture_rect(item[1], Rect2((size * item[0]).floor(), Vector2.ONE * tile * PRESENTATION.backdrop_landmark_scale), false)
	for index in range(PRESENTATION.backdrop_ant_count):
		var position: Vector2 = ant_position(index)
		var heading := Vector2.RIGHT if index % 2 == 0 else Vector2.DOWN
		var phase: float = sin(_time * PRESENTATION.backdrop_ant_stride_frequency + index)
		_draw_ant(position.floor(), heading, PRESENTATION.backdrop_ant_scale, phase, Color.WHITE)
		if index % 3 == 0:
			_draw_cargo(position.floor(), heading, PRESENTATION.backdrop_ant_scale, index)
	_draw_spiders()

func _draw_marker_grain() -> void:
	# Sparse dry-marker strokes texture the background while leaving actors readable.
	for stroke in range(PRESENTATION.backdrop_grain_count):
		var x: float = fposmod(sin(float(stroke) * 12.9898) * 43758.5453, 1.0) * size.x
		var y: float = fposmod(sin(float(stroke) * 78.233 + 4.17) * 24634.6345, 1.0) * size.y
		var length: float = 3.0 + float(stroke % 4)
		var color := ColonyStyle.color(&"backdrop_grain")
		draw_line(Vector2(x, y), Vector2(x + length, y + length * 0.22), color, 1.0)

func _draw_ant(position: Vector2, forward: Vector2, scale_value: float, phase: float, tint: Color) -> void:
	var side := Vector2(-forward.y, forward.x)
	var leg_color := ColonyStyle.color(&"ant_legs").darkened(0.08)
	for pair in range(3):
		var origin: Vector2 = position + forward * (pair - 1) * 2.2 * scale_value
		for sign_value in [-1.0, 1.0]:
			var foot: Vector2 = origin + side * sign_value * 3.2 * scale_value + forward * phase * sign_value * scale_value
			draw_line(origin.round(), foot.round(), leg_color, maxf(1.0, scale_value))
	draw_circle(position - forward * 3.0 * scale_value, 2.3 * scale_value, ColonyStyle.color(&"ant_abdomen") * tint)
	draw_circle(position, 1.45 * scale_value, ColonyStyle.color(&"ant_thorax") * tint)
	draw_circle(position + forward * 3.0 * scale_value, 1.8 * scale_value, ColonyStyle.color(&"ant_head") * tint)
	for sign_value in [-1.0, 1.0]:
		draw_line(position + forward * 4.3 * scale_value, position + forward * 6.1 * scale_value + side * sign_value * 1.8 * scale_value, leg_color, maxf(1.0, scale_value))

func _draw_cargo(position: Vector2, heading: Vector2, scale_value: float, index: int) -> void:
	var side := Vector2(-heading.y, heading.x)
	var cargo_position := position - heading * 4.0 * scale_value - side * 2.0 * scale_value
	var cargo_color := ColonyStyle.color(&"carried_goods") if index % 2 == 0 else ColonyStyle.color(&"carried_leaves")
	draw_rect(Rect2((cargo_position - Vector2.ONE * 2.0 * scale_value).round(), Vector2.ONE * 4.0 * scale_value), cargo_color)
	draw_rect(Rect2((cargo_position - Vector2.ONE * 2.0 * scale_value).round(), Vector2.ONE * 4.0 * scale_value), ColonyStyle.color(&"ant_legs"), false, 1.0)

func _draw_spiders() -> void:
	# Spiders trail the two main worker routes; ants ahead keep moving with their loads.
	var tile: float = PRESENTATION.backdrop_tile_size
	var center := (size / tile / 2.0).floor() * tile + Vector2.ONE * tile / 2.0
	var horizontal_t: float = fposmod(_time * PRESENTATION.backdrop_ant_speed * PRESENTATION.backdrop_spider_speed_ratio + PRESENTATION.backdrop_spider_start_phase, 1.0)
	var vertical_t: float = fposmod(_time * PRESENTATION.backdrop_ant_speed * PRESENTATION.backdrop_spider_speed_ratio + PRESENTATION.backdrop_spider_start_phase, 1.0)
	var horizontal_spider := Vector2(horizontal_t * (size.x + PRESENTATION.backdrop_spider_overhang * 2.0) - PRESENTATION.backdrop_spider_overhang, center.y + PRESENTATION.backdrop_spider_lane_offset.y)
	var vertical_spider := Vector2(center.x + PRESENTATION.backdrop_spider_lane_offset.x, vertical_t * (size.y + PRESENTATION.backdrop_spider_overhang * 2.0) - PRESENTATION.backdrop_spider_overhang)
	_draw_spider(horizontal_spider, Vector2.RIGHT, sin(_time * PRESENTATION.backdrop_spider_stride_frequencies.x))
	_draw_spider(vertical_spider, Vector2.DOWN, cos(_time * PRESENTATION.backdrop_spider_stride_frequencies.y))

func _draw_spider(position: Vector2, forward: Vector2, phase: float) -> void:
	var side := Vector2(-forward.y, forward.x)
	var leg_color := ColonyStyle.color(&"backdrop_spider_legs")
	for pair in range(4):
		var origin: Vector2 = position + forward * (float(pair) - 1.5) * 2.1
		for sign_value in [-1.0, 1.0]:
			var joint: Vector2 = origin + side * sign_value * (5.0 + absf(phase))
			var foot: Vector2 = joint + forward * (phase * sign_value + (float(pair) - 1.5) * 1.2) + side * sign_value * 3.0
			draw_line(origin.round(), joint.round(), leg_color, 1.5)
			draw_line(joint.round(), foot.round(), leg_color, 1.5)
	draw_circle(position - forward * 2.0, 4.0, ColonyStyle.color(&"backdrop_spider_body"))
	draw_circle(position + forward * 2.5, 2.8, ColonyStyle.color(&"backdrop_spider_head"))
	draw_circle(position + forward * 3.8 + side * 1.0, 0.8, ColonyStyle.color(&"backdrop_spider_eyes"))
	draw_circle(position + forward * 3.8 - side * 1.0, 0.8, ColonyStyle.color(&"backdrop_spider_eyes"))

## Ant routes follow the crossed roads layered over the shader-rendered ground.
func ant_position(index: int) -> Vector2:
	var t: float = fmod(_time * PRESENTATION.backdrop_ant_speed + float(index) / maxi(1, PRESENTATION.backdrop_ant_count), 1.0)
	var lane: float = (index % 5 - 2) * 2.0 + sin(_time * PRESENTATION.backdrop_lane_sway.x + float(index)) * PRESENTATION.backdrop_lane_sway.y
	var tile: float = PRESENTATION.backdrop_tile_size
	var center := (size / tile / 2.0).floor() * tile + Vector2.ONE * tile / 2.0
	var overhang := PRESENTATION.backdrop_ant_overhang
	if index % 2 == 0:
		return Vector2(t * (size.x + overhang * 2) - overhang, center.y + lane)
	return Vector2(center.x + lane, t * (size.y + overhang * 2) - overhang)
