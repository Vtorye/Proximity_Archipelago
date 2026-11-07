class_name NavigationPanel
extends PanelContainer
## Compact key and live enterprise breakdown, separate from the world labels.
var overlay: NavigationOverlay
var inspected_building: Building
var _legend: VBoxContainer
var _heading: Label
var _source: Label
var _detail: Label
var _elapsed := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = 190
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 3)
	add_child(content)
	_legend = VBoxContainer.new()
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_theme_constant_override("separation", 3)
	content.add_child(_legend)
	_heading = _line(_legend, "", ColonyStyle.ACCENT)
	_source = _line(_legend, "")
	_line(_legend, "Меньше число — выше приоритет")
	_line(_legend, "Путь + 0.5 × (работают + идут)")
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_legend.add_child(row)
	_line(row, "Земля", NavigationOverlay.COLORS[&"terrain"])
	_line(row, "Работа", NavigationOverlay.COLORS[&"work"])
	_line(row, "Дом", NavigationOverlay.COLORS[&"home"])
	_line(row, "Еда", NavigationOverlay.COLORS[&"food"])
	_detail = _line(content, "Наведите курсор на предприятие")
	_detail.custom_minimum_size.x = 172
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refresh()
func _line(parent: Node, text: String, color: Color = ColonyStyle.TEXT) -> Label:
	var label: Label = ColonyStyle.label(text, 4, color)
	label.add_theme_font_override("font", ColonyStyle.SECONDARY_FONT)
	label.add_theme_font_size_override("font_size", 8)
	parent.add_child(label)
	return label
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		refresh()
func inspect(building: Building) -> void:
	inspected_building = building
	refresh()

func refresh() -> void:
	if not is_instance_valid(inspected_building) or not inspected_building.is_inside_tree():
		inspected_building = null
	var show_routes: bool = overlay != null and overlay.mode > 0
	var terrain: TileData
	if overlay != null and overlay.hover_active:
		var map: TileMapLayer = overlay.world.get_node("Map")
		terrain = map.get_cell_tile_data(overlay.hovered)
	mouse_filter = Control.MOUSE_FILTER_STOP if show_routes or inspected_building != null else Control.MOUSE_FILTER_IGNORE
	visible = show_routes or inspected_building != null or terrain != null
	if not visible:
		return
	_legend.visible = show_routes
	if show_routes:
		_heading.text = "Вход в клетку · мс" if overlay.mode == 1 else "Приоритеты · секунды"
		_source.text = "От (%d, %d) · скорость %.1f" % [overlay.origin.x, overlay.origin.y, overlay.reference_speed]
	var cell: Vector2i = inspected_building.cell if inspected_building != null else overlay.hovered
	var value: Dictionary = overlay.sample(cell) if show_routes or terrain != null else {}
	var building: Building = inspected_building if inspected_building != null else value.get("building")
	if building is Workplace:
		var workload: String = tr("ui.hud.workload") % [building.working_count(), building.incoming_count(), building.work_slots]
		_detail.text = "%s\n%s" % [tr(building.display_title()), workload]
		if building.recipe == null and building.output != null:
			_detail.text += "\n" + (tr("ui.source.remaining") % building.remaining_supply if building.finite_supply else tr("ui.source.infinite"))
		if show_routes:
			_detail.text += "\n" + overlay.explanation(building)
	elif building is House:
		_detail.text = _stock_details(building)
	elif building != null:
		_detail.text = tr(building.display_title())
		if show_routes:
			_detail.text += "\n" + ("Пути нет" if not is_finite(value.seconds) else "Путь: %.2f с" % value.seconds)
	elif terrain != null:
		var time: float = overlay.world.planner.travel_seconds(overlay.world.route_service.entry_cost(cell), overlay.reference_speed)
		_detail.text = "%s\n%s" % [tr(terrain.get_custom_data("terrain_name")), (tr("ui.terrain.entry") % roundi(time * 1000)) if is_finite(time) else tr("ui.terrain.impassable")]
	else:
		_detail.text = "Клик — нагрузка предприятия\nПКМ — выбрать начало\nЛКМ / стрелки — камера\nГолод проверяется отдельно"
	_detail.add_theme_color_override("font_color", value.get("color", ColonyStyle.TEXT))
	size.y = get_combined_minimum_size().y

func _stock_details(house: House) -> String:
	var inventory: WorldInventory = overlay.world.inventory
	var is_main: bool = house.is_main_nest
	var lines := PackedStringArray([tr("ui.storage.main" if is_main else "ui.storage.local")])
	if not is_main:
		lines.append(tr("ui.storage.fill") % [inventory.depot_fill(house), house.storage_capacity])
	for type in inventory.registered_types():
		var count: int = inventory.nest_quantity(house, overlay.world.logistics.main_nest, type)
		lines.append("%s · %d" % [tr(type.display_name), count])
	return "\n".join(lines)
