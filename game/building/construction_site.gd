class_name ConstructionSite
extends Building
## A non-operational reservation. Materials and assembly progress belong to this site.
var service: ConstructionService
var candidate: Building
var crates: Dictionary = {}
var delivered: Dictionary[StringName, int] = {}
var transit: Dictionary[StringName, int] = {}
var required: Array[ResourceAmount] = []
var progress := 0.0
var builder: AntAgent
var active := true

func material_count() -> int:
	var count := 0
	for amount: int in delivered.values(): count += amount
	return count

func supplied() -> bool:
	for item in required:
		if delivered.get(item.type.id, 0) < item.amount: return false
	return true

func route(from_cell: Vector2i) -> Route:
	return service.controller.route_service.route_to_any(from_cell, entry_cells())

func route_lower_bound(grid: TileGrid, from_cell: Vector2i) -> float:
	var lowest := INF
	for entry in entry_cells(): lowest = minf(lowest, grid.path_lower_bound(from_cell, entry))
	return lowest

func display_title() -> String:
	return TranslationServer.translate("ui.site.title") % TranslationServer.translate(option.display_name)

func details() -> String:
	var lines := PackedStringArray([display_title()])
	for item in required:
		lines.append("%s: %d / %d" % [TranslationServer.translate(item.type.display_name), delivered.get(item.type.id, 0), item.amount])
	lines.append(TranslationServer.translate("ui.site.assembly") % roundi(progress / option.construction_seconds * 100) if supplied() else TranslationServer.translate("ui.site.delivery"))
	return "\n".join(lines)

func _on_demolish() -> void:
	if active: service.cancel(self)

func _exit_tree() -> void:
	if is_instance_valid(candidate): candidate.free()

func _draw() -> void:
	if service == null: return
	var size: float = service.controller.route_service.cell_size()
	var rect := Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size)
	var icon: Texture2D = service.art.build_icon(option)
	if icon != null: draw_texture_rect(icon, rect, false, Color(1, 1, 1, 0.38))
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var point: Vector2 = corner * (size * 0.5 - 2)
		draw_line(point, point - Vector2(corner.x * 3, 0), Color("d7bc73"), 1)
		draw_line(point, point - Vector2(0, corner.y * 3), Color("d7bc73"), 1)
	var fraction: float = progress / option.construction_seconds if supplied() else float(material_count()) / maxi(1, WorldInventory.cargo_size(required)) * 0.5
	for index in range(3):
		draw_rect(Rect2(-4 + index * 3, size * 0.5 - 4, 2, 2), Color("d7bc73") if fraction >= float(index + 1) / 3.0 else Color("423d32"))
