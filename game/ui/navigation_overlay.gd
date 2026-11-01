class_name NavigationOverlay
extends Node2D
## One shared distance field explains the same entry costs and load term as TripPlanner.
const COLORS := {&"terrain": Color("b9b9b4"), &"work": Color("ff9184"), &"home": Color("8dbdff"), &"food": Color("9de3a0")}
var world: World
var mode := 0
var origin := Vector2i.ZERO
var hovered := Vector2i.ZERO
var reference_speed := 24.0
var obstacles: Array[Rect2] = []
var _field: NavigationField
var _revision := -1
var _refresh := 0.0
var _points: Dictionary[Vector2i, Building] = {}

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
	_refresh_points()

func _refresh_points() -> void:
	_points.clear()
	for building in world.registry.all():
		for cell in building.footprint(): _points[cell] = building

func _ready() -> void:
	world.registry.changed.connect(_refresh_points)

func _process(delta: float) -> void:
	if mode == 0: return
	var ants: Array[AntAgent] = world.population.agents()
	if not ants.is_empty(): reference_speed = ants[0].speed
	_refresh += delta
	if _revision != world.route_service.revision: _update_field()
	if _refresh >= 0.25:
		_refresh = 0.0
		queue_redraw()

func sample(cell: Vector2i) -> Dictionary:
	var building: Building = _points.get(cell)
	var kind: StringName = &"terrain"
	if building is House: kind = &"home"
	elif building is Canteen: kind = &"food"
	elif building is Workplace:
		kind = &"food" if _produces_food(building) else &"work"
	var travel := INF
	if _field != null:
		if building != null:
			for entry in building.entry_cells(): travel = minf(travel, world.planner.travel_seconds(_field.cost(entry), reference_speed))
		else: travel = world.planner.travel_seconds(_field.cost(cell), reference_speed)
	var load: int = building.worker_count() if building is Workplace else 0
	var score: float = travel + TripPlanner.LOAD_PENALTY_SECONDS * load
	return {"building": building, "kind": kind, "color": COLORS[kind], "seconds": travel, "load": load, "score": score}

func _produces_food(workplace: Workplace) -> bool:
	if workplace.output != null and workplace.output.id == &"food": return true
	if workplace.recipe != null:
		for entry in workplace.recipe.outputs:
			if entry.type.id == &"food": return true
	return false

func explanation(workplace: Workplace) -> String:
	var value: Dictionary = sample(workplace.cell)
	if not is_finite(value.seconds): return "Из выбранной точки пути нет"
	return "%.2f с + 0.5 × %d = %.2f%s" % [value.seconds, value.load, value.score, " · мест нет" if not workplace.has_free_slot() else ""]

func _draw() -> void:
	if mode == 0 or _field == null: return
	var map: TileMapLayer = world.get_node("Map")
	var canvas: Transform2D = map.get_global_transform_with_canvas()
	var screen_size: Vector2 = Vector2(map.tile_set.tile_size) * canvas.get_scale()
	var font: Font = ColonyStyle.SECONDARY_FONT
	var view: Rect2 = get_viewport_rect()
	# Visit only visible cells. A larger ocean never adds work to the overlay.
	var first: Vector2i = map.local_to_map(canvas.affine_inverse() * view.position) - Vector2i.ONE
	var last: Vector2i = map.local_to_map(canvas.affine_inverse() * view.end) + Vector2i.ONE
	draw_set_transform_matrix(get_global_transform_with_canvas().affine_inverse())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if not world.route_service.walkable(cell) and not _points.has(cell): continue
			var center: Vector2 = (canvas * map.map_to_local(cell)).round()
			if not view.has_point(center) or center.y < 50 or center.y > view.end.y - 72: continue
			var blocked := false
			for obstacle in obstacles: blocked = blocked or obstacle.has_point(center)
			if blocked: continue
			var value: Dictionary = sample(cell)
			var seconds: float = world.planner.travel_seconds(world.route_service.entry_cost(cell), reference_speed) if mode == 1 else value.score
			var color: Color = value.color
			draw_rect(Rect2(center - screen_size * 0.5, screen_size), Color(color.r * 0.45, color.g * 0.45, color.b * 0.45, 0.82))
			if screen_size.x < 26: continue
			var text: String = "—" if not is_finite(seconds) else ("%d" % roundi(seconds * 1000) if mode == 1 else "%.1f" % seconds)
			var text_position: Vector2 = center + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / 2, 3)
			draw_string(font, text_position + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.BLACK)
			draw_string(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
