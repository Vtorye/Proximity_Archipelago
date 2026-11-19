class_name NavigationPanel
extends PanelContainer
## Compact key and live enterprise breakdown, separate from the world labels.
var overlay: NavigationOverlay
var inspected_cell: Variant = null
@onready var _legend: VBoxContainer = %Legend
@onready var _heading: Label = %Heading
@onready var _source: Label = %Source
@onready var _detail: RichTextLabel = %Detail
@onready var _clear_trap: Button = %ClearTrap
@onready var _header: WindowHeader = %WindowHeader
var _trap_cell := Vector2i.ZERO
var _elapsed := 0.0
func _ready() -> void:
	_clear_trap.pressed.connect(AppSettings.play_click)
	_clear_trap.pressed.connect(func():
		if overlay.world.combat != null:
			overlay.world.combat.clear_trap(_trap_cell)
		refresh())
	if overlay != null:
		configure(overlay)

func configure(routes: NavigationOverlay) -> void:
	overlay = routes
	%Formula.text = tr("ui.nav.formula") % str(overlay.world.planner.load_penalty_seconds)
	refresh()

func _process(delta: float) -> void:
	if overlay == null: return
	_elapsed += delta
	if _elapsed >= NavigationOverlay.PRESENTATION.navigation_refresh:
		_elapsed = 0.0
		refresh()
func inspect_cell(cell: Variant) -> void:
	inspected_cell = cell
	refresh()

func refresh() -> void:
	if overlay == null:
		return
	var show_routes: bool = overlay.mode > 0
	var cell: Vector2i = inspected_cell if inspected_cell != null else overlay.hovered
	var map: TileMapLayer = overlay.world.map
	var terrain: TileData = map.get_cell_tile_data(cell) if inspected_cell != null or overlay.hover_active or show_routes else null
	var building: Building = overlay.world.build_controller.demolition_target(cell) if terrain != null else null
	var combat: CombatDirector = overlay.world.combat
	var has_trap: bool = terrain != null and combat != null and combat.traps.has(cell)
	_clear_trap.visible = has_trap and inspected_cell != null
	%TrapPrice.visible = _clear_trap.visible
	if has_trap:
		_trap_cell = cell
		_clear_trap.text = "ui.trap.clear_action"
		if _clear_trap.visible:
			BuildCostText.show_price(%TrapPrice, combat.rules.trap_removal_costs, tr("ui.construction.price"))
		_clear_trap.disabled = not overlay.world.inventory.can_afford_all(combat.rules.trap_removal_costs)
	mouse_filter = Control.MOUSE_FILTER_STOP if show_routes or inspected_cell != null else Control.MOUSE_FILTER_IGNORE
	visible = show_routes or building != null or has_trap or (inspected_cell != null and terrain != null)
	if not visible:
		return
	_header.set_title("ui.nav.terrain" if inspected_cell != null and terrain != null else "ui.window.navigation")
	_legend.visible = show_routes
	if show_routes:
		_heading.text = "ui.nav.entry" if overlay.mode == 1 else "ui.nav.priority"
		_source.text = tr("ui.nav.origin") % [overlay.origin.x, overlay.origin.y, overlay.reference_speed]
	var value: Dictionary = overlay.sample(cell) if show_routes or terrain != null else {}
	var description := ""
	var product: ResourceType
	if has_trap:
		description = tr("ui.trap.title") + "\n" + tr("ui.trap.hint")
		if inspected_cell == null:
			description += "\n" + tr("ui.trap.inspect")
	elif building is ConstructionSite:
		description = building.display_title() + "\n" + building.assembly_status()
	elif building is Workplace:
		var workload: String = tr("ui.hud.workload") % [building.working_count(), building.incoming_count(), building.work_slots]
		description = "%s\n%s" % [tr(building.display_title()), workload]
		if building.recipe == null and building.output != null:
			description += "\n" + (tr("ui.source.remaining") % building.remaining_supply if building.finite_supply and overlay.world.inventory.quantities_known else tr("ui.source.infinite"))
			description += "\n" + tr("ui.construction.production_rate") % String.num(building.resource_rate(), 2)
			product = building.output
		if show_routes:
			description += "\n" + overlay.explanation(building)
	elif building is House:
		description = _stock_header(building)
	elif building != null:
		description = tr(building.display_title())
		if building is DefenseBuilding and building.kind == DefenseBuilding.Kind.TOWER:
			description += "\n" + tr("ui.tower.active" if building.staffed() else "ui.tower.inactive")
		if show_routes:
			description += "\n" + (tr("ui.nav.no_path") if not is_finite(value.seconds) else tr("ui.nav.path") % value.seconds)
	elif terrain != null:
		var time: float = overlay.world.planner.travel_seconds(overlay.world.route_service.entry_cost(cell), overlay.reference_speed)
		description = (tr("ui.terrain.entry") % roundi(time * 1000)) if is_finite(time) else tr("ui.terrain.impassable")
	else:
		description = tr("ui.nav.howto")
	if building is Workplace and not is_equal_approx(building.terrain_yield_multiplier, 1):
		description += "\n" + tr("ui.terrain.harvest") % roundi(building.terrain_yield_multiplier * 100)
	if building is House and building.terrain_capacity_multiplier > 1:
		description += "\n" + tr("ui.terrain.capacity_bonus") % roundi((building.terrain_capacity_multiplier - 1) * 100)
	if combat != null and building != null and combat.is_spider_target(building):
		description += "\n" + tr("ui.combat.health") % [combat.health(building), combat.maximum_health(building)]
	if inspected_cell != null and terrain != null and map is TerrainMap:
		var ground: TerrainType = map.ground_at(cell)
		var surface: TerrainType = map.surface_at(cell)
		var soil := TerrainRules.describe(ground)
		if surface != null and surface != ground:
			soil = tr(surface.display_name) + "\n" + soil
		if not soil.is_empty():
			description += "\n\n" + soil
	_detail.clear()
	_detail.add_text(description)
	if inspected_cell != null and not has_trap and building is House:
		_append_stock(building)
	elif not has_trap and building is ConstructionSite:
		for item in building.required:
			_detail.add_text("\n")
			BuildCostText.append_resource(_detail, item.type, "%d / %d" % [building.delivered.get(item.type.id, 0), item.amount])
	elif product != null:
		_detail.add_text("\n" + tr("ui.construction.production_resource") + " ")
		BuildCostText.append_resource(_detail, product)
	_detail.add_theme_color_override("default_color", value.get("color", ColonyStyle.color(&"text")))

func _stock_header(house: House) -> String:
	var inventory: WorldInventory = overlay.world.inventory
	var is_main: bool = house.is_main_nest
	var used: int = inventory.storage_load(null if overlay.world.logistics.main_nest == house else house) if is_main else inventory.depot_fill(house)
	var capacity: int = WorldInventory.base_capacity() if is_main else house.storage_capacity
	return tr("ui.storage.main" if is_main else "ui.storage.local") + "\n" + tr("ui.storage.fill") % [used, capacity]

func _append_stock(house: House) -> void:
	var inventory: WorldInventory = overlay.world.inventory
	for type in inventory.registered_types():
		if type.id == WorldInventory.CURRENCY_ID:
			continue
		var id: String = str(type.id)
		var count: int = inventory.nest_quantity(house, overlay.world.logistics.main_nest, type)
		_detail.add_text("\n")
		BuildCostText.append_resource(_detail, type, inventory.display_amount(type, count))
		var order: Dictionary = house.order_of(id)
		if not order.is_empty():
			_detail.add_text("\n  " + tr("ui.order.range") % [order.min, order.max])
		var owed: int = int(house.requests.get(id, 0))
		if owed != 0:
			_detail.add_text("\n  " + tr("ui.order.owed") % owed)
		var arriving: int = int(house.incoming.get(id, 0))
		if arriving > 0:
			_detail.add_text("\n  " + tr("ui.order.arriving") % arriving)
