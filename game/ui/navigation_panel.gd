class_name NavigationPanel
extends PanelContainer
## Compact key and live enterprise breakdown, separate from the world labels.
var overlay: NavigationOverlay
var inspected_cell: Variant = null
@onready var _legend: VBoxContainer = %Legend
@onready var _heading: Label = %Heading
@onready var _source: Label = %Source
@onready var _detail: Label = %Detail
@onready var _clear_trap: Button = %ClearTrap
var _trap_cell := Vector2i.ZERO
var _elapsed := 0.0
func _ready() -> void:
	%Formula.text = tr("ui.nav.formula") % str(overlay.world.planner.load_penalty_seconds)
	_clear_trap.pressed.connect(AppSettings.play_click)
	_clear_trap.pressed.connect(func():
		if overlay.world.combat != null:
			overlay.world.combat.clear_trap(_trap_cell)
		refresh())
	refresh()

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
	var map: TileMapLayer = overlay.world.map
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
		_heading.text = "ui.nav.entry" if overlay.mode == 1 else "ui.nav.priority"
		_source.text = tr("ui.nav.origin") % [overlay.origin.x, overlay.origin.y, overlay.reference_speed]
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
			_detail.text += "\n" + (tr("ui.nav.no_path") if not is_finite(value.seconds) else tr("ui.nav.path") % value.seconds)
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
		_detail.text = tr("ui.nav.howto")
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
