class_name NestMenu
extends MenuBase
## Per-building inventory and orders, with resident management for nests.

var world: World
var house: House
var canteen: Canteen
var controls: Dictionary[StringName, Button] = {}
@onready var _inventory_tab: VBoxContainer = %InventoryTab
@onready var _residents_tab: VBoxContainer = %ResidentsTab
var _stock_labels: Dictionary[StringName, RichTextLabel] = {}
var _role_labels: Dictionary[int, Label] = {}
var _purchase_labels: Dictionary[int, RichTextLabel] = {}
@onready var _population: Label = %Population
@onready var _capacity: Label = %Capacity
@onready var _orders_tab: VBoxContainer = %OrdersTab
var _order_rows: Dictionary[String, Dictionary] = {}
@onready var _funds: CheckButton = %Funds
@onready var _dialog: PanelContainer = %Dialog

func _ready() -> void:
	if not payload is Dictionary:
		close_requested.emit.call_deferred(self)
		return
	world = payload.get("world") as World
	var building := payload.get("building") as Building
	house = building as House
	canteen = building as Canteen
	if not is_instance_valid(world) or (house == null and canteen == null) or not world.logistics.owns(building):
		close_requested.emit.call_deferred(self)
		return
	var is_canteen := canteen != null
	%Title.visible = not is_canteen
	if is_canteen:
		%WindowHeader.set_title(canteen.display_title())
	else:
		%Title.text = house.display_title()
	controls[&"close"] = %WindowHeader.toggle
	%WindowHeader.close_requested.connect(func(): close_requested.emit(self))
	controls[&"inventory"] = %Inventory
	%Inventory.pressed.connect(AppSettings.play_click)
	%Inventory.pressed.connect(_show_tab.bind(&"inventory"))
	controls[&"orders"] = %Orders
	%Orders.pressed.connect(AppSettings.play_click)
	%Orders.pressed.connect(_show_tab.bind(&"orders"))
	%Residents.visible = not is_canteen
	_funds.visible = not is_canteen
	for type in world.inventory.registered_types():
		if type.id == WorldInventory.CURRENCY_ID or (is_canteen and type.id != WorldInventory.FOOD_ID):
			continue
		var line: RichTextLabel = preload("res://game/ui/nest_stock_label.tscn").instantiate()
		_stock_labels[type.id] = line
		_inventory_tab.add_child(line)
		var row: HBoxContainer = preload("res://game/ui/nest_order_row.tscn").instantiate()
		var minimum: SpinBox = row.get_node("Minimum")
		var maximum: SpinBox = row.get_node("Maximum")
		var owed: SpinBox = row.get_node("Owed")
		var order_limit := canteen.food_capacity if is_canteen else WorldInventory.order_limit()
		minimum.max_value = order_limit
		maximum.max_value = order_limit
		owed.max_value = WorldInventory.order_limit()
		owed.min_value = 0 if is_canteen else -WorldInventory.order_limit()
		owed.tooltip_text = "ui.canteen.once_hint" if is_canteen else "ui.storage.signed_request"
		minimum.tooltip_text = "ui.canteen.min_hint" if is_canteen else "ui.order.min_hint"
		maximum.tooltip_text = "ui.canteen.max_hint" if is_canteen else "ui.order.max_hint"
		minimum.value_changed.connect(_set_order.bind(str(type.id), "min"))
		maximum.value_changed.connect(_set_order.bind(str(type.id), "max"))
		owed.value_changed.connect(_set_owed.bind(str(type.id)))
		%OrderRows.add_child(row)
		_order_rows[str(type.id)] = {
			"name": row.get_node("Resource"), "type": type,
			"spins": {"min": minimum, "max": maximum, "once": owed},
		}
	if is_canteen:
		canteen.food_request_changed.connect(refresh)
	else:
		_setup_residents()
	world.inventory.changed.connect(refresh)
	building.tree_exiting.connect(func(): close_requested.emit(self))
	AppSettings.language_changed.connect(refresh)
	_show_tab(&"inventory")
	refresh()
	default_focus = controls[&"close"]

func _setup_residents() -> void:
	controls[&"residents"] = %Residents
	%Residents.pressed.connect(AppSettings.play_click)
	%Residents.pressed.connect(_show_tab.bind(&"residents"))
	_funds.toggled.connect(func(enabled: bool):
		if is_instance_valid(house):
			house.funds_construction = enabled)
	for role in world.population.roles():
		var row: HBoxContainer = preload("res://game/ui/nest_resident_row.tscn").instantiate()
		_role_labels[role] = row.get_node("Labels/Count")
		_purchase_labels[role] = row.get_node("Labels/Price")
		var buy: Button = row.get_node("Buy")
		buy.pressed.connect(AppSettings.play_click)
		buy.pressed.connect(_recruit.bind(role))
		controls[_control_key("buy", role)] = buy
		var kill: Button = row.get_node("Kill")
		kill.pressed.connect(AppSettings.play_click)
		kill.pressed.connect(_kill.bind(role))
		controls[_control_key("kill", role)] = kill
		_residents_tab.add_child(row)
	_residents_tab.move_child(%Assigned, -1)
	world.population.changed.connect(refresh)

func panel_bounds() -> Rect2:
	return _dialog.get_global_rect()

func _show_tab(key: StringName) -> void:
	_inventory_tab.visible = key == &"inventory"
	_orders_tab.visible = key == &"orders"
	_residents_tab.visible = key == &"residents"
	controls[key].set_pressed_no_signal(true)

func _set_order(value: float, id: String, field: String) -> void:
	if is_instance_valid(house):
		house.set_order(id, field, roundi(value))
	elif is_instance_valid(canteen):
		canteen.set_food_order(field, roundi(value))
	refresh()

## The value is saved as soon as it changes; it is the total still owed for this resource.
func _set_owed(value: float, id: String) -> void:
	if is_instance_valid(house):
		house.request(id, roundi(value))
		refresh()
	elif is_instance_valid(canteen):
		canteen.request_food(roundi(value))

func _recruit(role: AntAgent.Role) -> void:
	world.population.recruit(house, role)
	refresh()

func _kill(role: AntAgent.Role) -> void:
	world.population.kill_resident(house, role)
	refresh()

func refresh() -> void:
	if not is_instance_valid(world) or (not is_instance_valid(house) and not is_instance_valid(canteen)):
		return
	var used: int
	var capacity: int
	if is_instance_valid(canteen):
		used = world.inventory.depot_fill(canteen)
		capacity = canteen.food_capacity
	elif house.is_main_nest:
		used = world.inventory.storage_load(world.logistics.store_of(house))
		capacity = WorldInventory.base_capacity()
	else:
		used = world.inventory.depot_fill(house)
		capacity = house.storage_capacity
	_capacity.text = tr("ui.storage.fill") % [used, capacity] if world.inventory.quantities_known else tr("ui.storage.unlimited")
	for id in _order_rows:
		var row: Dictionary = _order_rows[id]
		var type: ResourceType = row.type
		var stock: int
		var minimum: int
		var maximum: int
		var owed: int
		if is_instance_valid(canteen):
			stock = world.inventory.depot_quantity(canteen, type)
			minimum = canteen.food_minimum
			maximum = canteen.food_maximum
			owed = canteen.requested_food
		else:
			stock = world.inventory.nest_quantity(house, world.logistics.main_nest, type)
			var order: Dictionary = house.order_of(id)
			minimum = int(order.min)
			maximum = int(order.max)
			owed = int(house.requests.get(id, 0))
		_show_stock(_stock_labels[type.id], type, stock)
		_show_stock(row.name, type, stock)
		var spins: Dictionary = row.spins
		(spins["min"] as SpinBox).set_value_no_signal(minimum)
		(spins["max"] as SpinBox).set_value_no_signal(maximum)
		(spins["once"] as SpinBox).set_value_no_signal(owed)
	if is_instance_valid(house):
		_refresh_residents()

func _refresh_residents() -> void:
	_funds.set_pressed_no_signal(house.funds_construction)
	_population.text = tr("ui.nest.population") % [house.residents.size(), house.resident_limit()]
	_population.tooltip_text = tr("ui.terrain.capacity_bonus") % roundi((house.terrain_capacity_multiplier - 1) * 100) if house.terrain_capacity_multiplier > 1 else ""
	var counts := {}
	for role in world.population.roles(): counts[role] = 0
	for ant: AntAgent in house.residents:
		counts[ant.role] += 1
	for role in counts:
		var title: String = tr("ui.nest." + AntAgent.Role.keys()[role].to_lower())
		_role_labels[role].text = "%s · %d" % [title, counts[role]]
		if role == AntAgent.Role.WARRIOR: _role_labels[role].tooltip_text = tr("ui.warrior.hint") % [world.waves.rules.warrior_health, world.waves.rules.attack_damage]
		controls[_control_key("kill", role)].disabled = counts[role] == 0
		var buy: Button = controls[_control_key("buy", role)]
		buy.disabled = not world.population.can_recruit(house, role)
		if world.population.recruitment != null:
			BuildCostText.show_price(_purchase_labels[role], world.population.recruitment.price(role))
		else:
			_purchase_labels[role].text = "—"
		buy.tooltip_text = "ui.nest.full" if not house.has_space() else ("ui.nest.unaffordable" if buy.disabled else "ui.nest.from_main")

func _show_stock(label: RichTextLabel, type: ResourceType, amount: int) -> void:
	label.clear()
	BuildCostText.append_resource(label, type, world.inventory.display_amount(type, amount))
	label.tooltip_text = type.display_name

func _control_key(action: String, role: int) -> StringName:
	return StringName(action + "_" + AntAgent.Role.keys()[role].to_lower())
