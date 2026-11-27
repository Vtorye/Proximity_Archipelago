class_name ConstructionSite
extends Building
## A non-operational reservation. Materials and assembly progress belong to this site.
@export_group("Appearance")
@export_range(0.0, 1.0, 0.01) var preview_opacity := 0.38
@export_range(0.0, 1.0, 0.01) var delivery_progress_share := 0.5
@export var corner_inset := 2.0
@export var corner_length := 3.0
@export_range(1, 12) var progress_indicators := 3
@export var indicator_size := Vector2(2, 2)
@export var indicator_spacing := 1.0
@export var indicator_bottom_inset := 4.0

var service: ConstructionService
var order: TaskBuildOrder
var candidate: Building
var crates: Dictionary = {}
var delivered: Dictionary[StringName, int] = {}
var transit: Dictionary[StringName, int] = {}
var required: Array[ResourceAmount] = []
var progress := 0.0
var builder: AntAgent
var active := true
var _field: NavigationField

func material_count() -> int:
	var count := 0
	for amount: int in delivered.values(): count += amount
	return count

func supplied() -> bool:
	for item in required:
		if delivered.get(item.type.id, 0) < item.amount: return false
	return true

func entry_cells() -> Array[Vector2i]:
	return service.controller.construction_entries(option, cell) if service != null else super.entry_cells()

func route(from_cell: Vector2i) -> Route:
	var navigation := service.controller.route_service
	if option is TileBuildOption and _field == null:
		# A tile has one entrance. Reuse a source field when available, with native A* as fallback.
		return navigation.request_route(from_cell, cell)
	return navigation.make_route(flow_field().path(from_cell))

func flow_field() -> NavigationField:
	var navigation: RouteService = service.controller.route_service
	if _field == null or _field.revision != navigation.revision:
		_field = navigation.reverse_field(entry_cells(), _field)
	return _field

func display_title() -> String:
	return TranslationServer.translate("ui.site.title") % TranslationServer.translate(option.display_name)

func assembly_status() -> String:
	if supplied():
		return TranslationServer.translate("ui.site.assembly") % roundi(progress / option.construction_seconds * 100)
	return TranslationServer.translate("ui.site.delivery")

func _on_demolish() -> void:
	if active: service.cancel(self)

func _exit_tree() -> void:
	if is_instance_valid(candidate): candidate.free()

func _draw() -> void:
	if service == null: return
	var size: float = service.controller.route_service.cell_size()
	var cells := footprint()
	var min_cell := cell
	var max_cell := cell
	for target in cells:
		min_cell.x = mini(min_cell.x, target.x)
		min_cell.y = mini(min_cell.y, target.y)
		max_cell.x = maxi(max_cell.x, target.x)
		max_cell.y = maxi(max_cell.y, target.y)
	var footprint_size := Vector2(max_cell - min_cell + Vector2i.ONE) * size
	var center_offset := (Vector2(min_cell + max_cell) * 0.5 - Vector2(cell)) * size
	var rect := Rect2(center_offset - footprint_size * 0.5, footprint_size)
	var icon: Texture2D = service.art.build_icon(option)
	if is_instance_valid(candidate):
		var sprite := candidate.get_node_or_null("Sprite") as Sprite2D
		if sprite != null and sprite.texture != null:
			icon = sprite.texture
	if icon != null: draw_texture_rect(icon, rect, false, Color(Color.WHITE, preview_opacity))
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var point: Vector2 = rect.get_center() + corner * (footprint_size * 0.5 - Vector2.ONE * corner_inset)
		draw_line(point, point - Vector2(corner.x * corner_length, 0), ColonyStyle.color(&"carried_goods"), 1)
		draw_line(point, point - Vector2(0, corner.y * corner_length), ColonyStyle.color(&"carried_goods"), 1)
	var fraction: float = progress / option.construction_seconds if supplied() else float(material_count()) / maxi(1, WorldInventory.cargo_size(required)) * delivery_progress_share
	var spacing := indicator_size.x + indicator_spacing
	var row_width := spacing * progress_indicators - indicator_spacing
	for index in range(progress_indicators):
		draw_rect(Rect2(Vector2(center_offset.x - row_width * 0.5 + index * spacing, rect.end.y - indicator_bottom_inset), indicator_size), ColonyStyle.color(&"carried_goods") if fraction >= float(index + 1) / progress_indicators else ColonyStyle.color(&"construction_tick_empty"))
