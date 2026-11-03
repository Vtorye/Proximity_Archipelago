class_name NavigationPanel
extends PanelContainer
## Compact key and live enterprise breakdown, separate from the world labels.
var overlay: NavigationOverlay
var _heading: Label
var _source: Label
var _detail: Label
var _elapsed := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = 190
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	add_child(content)
	_heading = _line(content, "", ColonyStyle.ACCENT)
	_source = _line(content, "")
	_line(content, "Меньше число — выше приоритет")
	_line(content, "Путь + 0.5 × (работают + идут)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
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
func refresh() -> void:
	visible = overlay != null and overlay.mode > 0
	if not visible: return
	_heading.text = "Вход в клетку · мс" if overlay.mode == 1 else "Приоритеты · секунды"
	_source.text = "От (%d, %d) · скорость %.1f" % [overlay.origin.x, overlay.origin.y, overlay.reference_speed]
	var value: Dictionary = overlay.sample(overlay.hovered)
	var building: Building = value.building
	if building is Workplace:
		_detail.text = "%s\n%d+%d/%d · работают + идут\n%s" % [tr(building.display_title()), building.working_count(), building.incoming_count(), building.work_slots, overlay.explanation(building)]
	elif building != null:
		_detail.text = "%s\n%s" % ["Муравейник" if building is House else "Столовая", "Пути нет" if not is_finite(value.seconds) else "Путь: %.2f с" % value.seconds]
	else: _detail.text = "Наведите курсор на предприятие\nПКМ — выбрать начало\nЛКМ / стрелки — камера\nГолод проверяется отдельно"
	_detail.add_theme_color_override("font_color", value.color)
