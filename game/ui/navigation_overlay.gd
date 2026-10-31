class_name NavigationOverlay
extends Node2D
## One shared distance field explains the same entry costs and load term as TripPlanner.
var world: World
var mode := 0
var origin := Vector2i.ZERO
var reference_speed := 24.0
var obstacles: Array[Rect2] = []
var _field: NavigationField
var _revision := -1
var _refresh := 0.0

func cycle() -> void:
	var ants: Array[AntAgent] = world.population.agents()
	if not ants.is_empty(): reference_speed = ants[0].speed
	mode = (mode + 1) % 3
	if mode > 0 and _field == null:
		for building in world.registry.all():
			if building is House:
				origin = building.cell
				break
	_update_field()
	queue_redraw()

func select_origin(cell: Vector2i) -> void:
	origin = cell
	_update_field()
	queue_redraw()

func _update_field() -> void:
	_field = world.route_service.distances_from(origin)
	_revision = world.route_service.revision

func _process(delta: float) -> void:
	if mode == 0: return
	var ants: Array[AntAgent] = world.population.agents()
	if not ants.is_empty(): reference_speed = ants[0].speed
	_refresh += delta
	if _revision != world.route_service.revision: _update_field()
	if _refresh >= 0.25:
		_refresh = 0.0
		queue_redraw()

func explanation(workplace: Workplace) -> String:
	if mode == 0 or _field == null: return ""
	var seconds := INF
	for cell in workplace.entry_cells():
		seconds = minf(seconds, world.planner.travel_seconds(_field.cost(cell), reference_speed))
	if not is_finite(seconds): return "Из выбранной точки пути нет"
	return "От точки: %.2f с + 0.5 × %d = %.2f%s" % [seconds, workplace.worker_count(), seconds + TripPlanner.LOAD_PENALTY_SECONDS * workplace.worker_count(), " · мест нет" if not workplace.has_free_slot() else ""]

func _draw() -> void:
	if mode == 0 or _field == null: return
	var map: TileMapLayer = world.get_node("Map")
	var size: Vector2 = Vector2(map.tile_set.tile_size) * map.scale
	var canvas: Transform2D = get_global_transform_with_canvas()
	draw_set_transform_matrix(canvas.affine_inverse())
	var screen_size: Vector2 = size * canvas.get_scale()
	var font: Font = ColonyStyle.SECONDARY_FONT
	var show_numbers: bool = screen_size.x >= 26
	var view: Rect2 = get_viewport_rect()
	for cell in map.get_used_cells():
		var center: Vector2 = (canvas * to_local(map.to_global(map.map_to_local(cell)))).round()
		if not view.has_point(center) or center.y < 50 or center.y > view.end.y - 72: continue
		var blocked := false
		for obstacle in obstacles: blocked = blocked or obstacle.has_point(center)
		if blocked: continue
		var cost: float = world.route_service.entry_cost(cell) if mode == 1 else _field.cost(cell)
		if not is_finite(cost): continue
		var seconds: float = world.planner.travel_seconds(cost, reference_speed)
		var rect := Rect2(center - screen_size * 0.5, screen_size)
		draw_rect(rect, Color(0.05, 0.1, 0.1, 0.65))
		if show_numbers:
			var text: String = "%d" % roundi(seconds * 1000) if mode == 1 else "%.1f" % seconds
			draw_string(font, center + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / 2, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ColonyStyle.TEXT)
	if mode == 2:
		# The legend uses screen pixels, independent of camera zoom.
		draw_set_transform_matrix(get_global_transform_with_canvas().affine_inverse())
		var row := 0
		for workplace in world.registry.workplaces():
			if row >= 7: break
			var text: String = workplace.display_title() + ": " + explanation(workplace)
			var position := Vector2(150, 62 + row * 12)
			draw_rect(Rect2(position - Vector2(2, 9), Vector2(minf(480, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 4), 12)), Color(0, 0, 0, 0.9))
			draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, 480, 8, ColonyStyle.ACCENT)
			row += 1
	var selected: Vector2 = canvas * to_local(world.route_service.cell_to_world(origin))
	draw_rect(Rect2(selected - screen_size / 2, screen_size), Color.WHITE, false, 1)
