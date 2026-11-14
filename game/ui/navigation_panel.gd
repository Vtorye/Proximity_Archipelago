class_name NavigationPanel
extends PanelContainer
## Compact key and live enterprise breakdown, separate from the world labels.
var overlay: NavigationOverlay
var inspected_cell: Variant = null
var _legend: VBoxContainer
var _heading: Label
var _source: Label
var _detail: Label
var _clear_trap: Button
var _trap_cell := Vector2i.ZERO
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
	_clear_trap = ColonyStyle.button("")
	_clear_trap.pressed.connect(func():
		if overlay.world.combat != null: overlay.world.combat.clear_trap(_trap_cell)
		refresh())
	content.add_child(_clear_trap)
	_clear_trap.hide()
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
func inspect_cell(cell: Variant) -> void:
	inspected_cell = cell
	refresh()

func refresh() -> void:
	var show_routes: bool = overlay.mode > 0
	var cell: Vector2i = inspected_cell if inspected_cell != null else overlay.hovered
	var map: TileMapLayer = overlay.world.get_node("Map")
	var terrain: TileData = map.get_cell_tile_data(cell) if inspected_cell != null or overlay.hover_active or show_routes else null
	var building: Building = overlay.world.build_controller.demolition_target(cell) if terrain != null else null
	var combat: CombatDirector = overlay.world.combat
	var has_trap: bool = terrain != null and combat != null and combat.traps.has(cell)
	_clear_trap.visible = has_trap and inspected_cell != null
	if has_trap:
		_trap_cell = cell
		_clear_trap.text = tr("ui.trap.clear") % BuildCostText.format(combat.rules.trap_removal_costs)
		_clear_trap.disabled = not overlay.world.inventory.can_afford_all(combat.rules.trap_removal_costs)
	mouse_filter = Control.MOUSE_FILTER_STOP if show_routes or inspected_cell != null else Control.MOUSE_FILTER_IGNORE
	visible = show_routes or terrain != null
	if not visible:
		return
	_legend.visible = show_routes
	if show_routes:
		_heading.text = "Вход в клетку · мс" if overlay.mode == 1 else "Приоритеты · секунды"
		_source.text = "От (%d, %d) · скорость %.1f" % [overlay.origin.x, overlay.origin.y, overlay.reference_speed]
	var value: Dictionary = overlay.sample(cell) if show_routes or terrain != null else {}
	if has_trap:
		_detail.text = tr("ui.trap.title") + "\n" + tr("ui.trap.hint")
		if inspected_cell == null:
			_detail.text += "\n" + tr("ui.trap.inspect")
	elif building is ConstructionSite:
		_detail.text = building.details()
	elif building is Workplace:
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
		if building is DefenseBuilding and building.kind == DefenseBuilding.Kind.TOWER:
			_detail.text += "\n" + tr("ui.tower.active" if building.staffed() else "ui.tower.inactive")
		if show_routes:
			_detail.text += "\n" + ("Пути нет" if not is_finite(value.seconds) else "Путь: %.2f с" % value.seconds)
	elif terrain != null:
		var time: float = overlay.world.planner.travel_seconds(overlay.world.route_service.entry_cost(cell), overlay.reference_speed)
		_detail.text = "%s\n%s" % [tr(terrain.get_custom_data("terrain_name")), (tr("ui.terrain.entry") % roundi(time * 1000)) if is_finite(time) else tr("ui.terrain.impassable")]
		if overlay.world.terrain != null:
			var soil: TerrainType = overlay.world.terrain.map.ground_at(cell)
			if soil != null:
				var surface: TerrainType = overlay.world.terrain.map.surface_at(cell)
				_detail.text = TerrainRules.describe(soil) + "\n" + ((tr("ui.terrain.entry") % roundi(time * 1000)) if is_finite(time) else tr("ui.terrain.impassable"))
				if surface != null and surface.kind == TerrainType.Kind.ROAD: _detail.text = tr(surface.display_name) + "\n" + _detail.text
	else:
		_detail.text = "Клик — нагрузка предприятия\nПКМ — выбрать начало\nЛКМ / стрелки — камера\nГолод проверяется отдельно"
	if building != null and not building is ConstructionSite and overlay.world.terrain != null:
		var soil: TerrainType = overlay.world.terrain.map.ground_at(cell)
		if soil != null:
			_detail.text += "\n" + tr("ui.terrain.base") % tr(soil.display_name)
			if building is Workplace and not is_equal_approx(building.terrain_yield_multiplier, 1): _detail.text += "\n" + tr("ui.terrain.harvest") % roundi(building.terrain_yield_multiplier * 100)
			if building is House and building.terrain_capacity_multiplier > 1: _detail.text += "\n" + tr("ui.terrain.capacity_bonus") % roundi((building.terrain_capacity_multiplier - 1) * 100)
	if combat != null and building != null and combat.health(building) > 0:
		_detail.text += "\n" + tr("ui.combat.health") % [combat.health(building), combat.maximum_health(building)]
	_detail.add_theme_color_override("font_color", value.get("color", ColonyStyle.TEXT))
	size.y = get_combined_minimum_size().y

func _stock_details(house: House) -> String:
	var inventory: WorldInventory = overlay.world.inventory
	var is_main: bool = house.is_main_nest
	var lines := PackedStringArray([tr("ui.storage.main" if is_main else "ui.storage.local")])
	var used: int = inventory.storage_load(null if overlay.world.logistics.main_nest == house else house) if is_main else inventory.depot_fill(house)
	var capacity: int = WorldInventory.base_capacity() if is_main else house.storage_capacity
	lines.append(tr("ui.storage.fill") % [used, capacity])
	for type in inventory.registered_types():
		if type.id == WorldInventory.CURRENCY_ID:
			continue
		var id: String = str(type.id)
		var count: int = inventory.nest_quantity(house, overlay.world.logistics.main_nest, type)
		lines.append("%s · %d" % [tr(type.display_name), count])
		var order: Dictionary = house.order_of(id)
		if not order.is_empty():
			lines.append("  " + tr("ui.order.range") % [order.min, order.max])
		var owed: int = int(house.requests.get(id, 0))
		if owed > 0:
			lines.append("  " + tr("ui.order.owed") % owed)
		var arriving: int = int(house.incoming.get(id, 0))
		if arriving > 0:
			lines.append("  " + tr("ui.order.arriving") % arriving)
	return "\n".join(lines)
