class_name NestMenu
extends MenuBase
## Per-nest inventory, assigned residents, and recruitment.

var world: World
var house: House
var controls: Dictionary[StringName, Button] = {}
@onready var _inventory_tab: VBoxContainer = %InventoryTab
@onready var _residents_tab: VBoxContainer = %ResidentsTab
var _stock_labels: Dictionary[StringName, Label] = {}
var _role_labels: Dictionary[int, Label] = {}
var _purchase_labels: Dictionary[int, Label] = {}
@onready var _population: Label = %Population
@onready var _capacity: Label = %Capacity
@onready var _orders_tab: VBoxContainer = %OrdersTab
var _order_rows: Dictionary[String, Dictionary] = {}
@onready var _funds: CheckButton = %Funds

func _ready() -> void:
	if not payload is Dictionary:
		close_requested.emit.call_deferred(self)
		return
	world = payload.get("world") as World
	house = payload.get("house") as House
	if not is_instance_valid(world) or not world.logistics.owns(house):
		close_requested.emit.call_deferred(self)
		return
	ColonyStyle.apply(self)
	if world.combat != null:
		%WindowHeader.panel_width = 480.0
	%Title.text = "ui.storage.main" if house.is_main_nest else "ui.storage.local"
	controls[&"close"] = %Close
	%Close.pressed.connect(AppSettings.play_click)
	%Close.pressed.connect(func(): close_requested.emit(self))
	controls[&"inventory"] = %Inventory
	%Inventory.pressed.connect(AppSettings.play_click)
	%Inventory.pressed.connect(_show_tab.bind(&"inventory"))
	controls[&"orders"] = %Orders
	%Orders.pressed.connect(AppSettings.play_click)
	%Orders.pressed.connect(_show_tab.bind(&"orders"))
	controls[&"residents"] = %Residents
	%Residents.pressed.connect(AppSettings.play_click)
	%Residents.pressed.connect(_show_tab.bind(&"residents"))
	for type in world.inventory.registered_types():
		var line: Label = ColonyStyle.label("")
		_stock_labels[type.id] = line
		_inventory_tab.add_child(line)
	_funds.toggled.connect(func(enabled: bool):
		if is_instance_valid(house):
			house.funds_construction = enabled)
	var order_grid: GridContainer = %OrderGrid
	for type in world.inventory.registered_types():
		if type.id == WorldInventory.CURRENCY_ID:
			continue
		var row := order_grid
		var name_label: Label = ColonyStyle.label("")
		name_label.custom_minimum_size.x = 110
		row.add_child(name_label)
		var spins: Dictionary = {}
		for field in ["min", "max"]:
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.max_value = WorldInventory.order_limit()
			spin.step = 1
			spin.custom_minimum_size.x = 72
			spin.value_changed.connect(_set_order.bind(str(type.id), field))
			row.add_child(spin)
			spins[field] = spin
		var once := SpinBox.new()
		once.min_value = 0
		once.max_value = WorldInventory.order_limit()
		once.step = 1
		once.custom_minimum_size.x = 72
		once.value_changed.connect(_set_owed.bind(str(type.id)))
		row.add_child(once)
		spins["once"] = once
		_order_rows[str(type.id)] = {"name": name_label, "spins": spins, "type": type}
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
	world.inventory.changed.connect(refresh)
	world.population.changed.connect(refresh)
	house.tree_exiting.connect(func(): close_requested.emit(self))
	_show_tab(&"inventory")
	refresh()
	default_focus = %Close

func _show_tab(key: StringName) -> void:
	_inventory_tab.visible = key == &"inventory"
	_orders_tab.visible = key == &"orders"
	_residents_tab.visible = key == &"residents"
	controls[key].set_pressed_no_signal(true)

func _set_order(value: float, id: String, field: String) -> void:
	if is_instance_valid(house):
		house.set_order(id, field, roundi(value))
		refresh()

## The value is saved as soon as it changes; it is the total still owed for this resource.
func _set_owed(value: float, id: String) -> void:
	if is_instance_valid(house):
		house.request(id, roundi(value))
		refresh()

func _recruit(role: AntAgent.Role) -> void:
	world.population.recruit(house, role)
	refresh()

func _kill(role: AntAgent.Role) -> void:
	world.population.kill_resident(house, role)
	refresh()

func refresh() -> void:
	if not is_instance_valid(house) or not is_instance_valid(world):
		return
	var main: bool = house.is_main_nest
	var used: int = world.inventory.storage_load(null if house == world.logistics.main_nest else house) if main else world.inventory.depot_fill(house)
	var capacity: int = WorldInventory.base_capacity() if main else house.storage_capacity
	_capacity.text = tr("ui.storage.fill") % [used, capacity]
	for type in world.inventory.registered_types():
		var amount: int = world.inventory.nest_quantity(house, world.logistics.main_nest, type)
		_stock_labels[type.id].text = "%s · %d" % [tr(type.display_name), amount]
	_funds.visible = true
	_funds.set_pressed_no_signal(house.funds_construction)
	for id in _order_rows:
		var row: Dictionary = _order_rows[id]
		var type: ResourceType = row.type
		var order: Dictionary = house.order_of(id)
		var stock: int = world.inventory.nest_quantity(house, world.logistics.main_nest, type)
		(row.name as Label).text = "%s · %d" % [tr(type.display_name), stock]
		var spins: Dictionary = row.spins
		for field in ["min", "max"]:
			(spins[field] as SpinBox).set_value_no_signal(int(order.get(field, 0)))
		# The owed field mirrors the saved total, which shrinks as carriers deliver.
		(spins["once"] as SpinBox).set_value_no_signal(int(house.requests.get(id, 0)))
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
		_purchase_labels[role].text = BuildCostText.format(world.population.recruitment.price(role)) if world.population.recruitment != null else "—"
		buy.tooltip_text = "ui.nest.full" if not house.has_space() else ("ui.nest.unaffordable" if buy.disabled else "ui.nest.from_main")

func _control_key(action: String, role: int) -> StringName:
	return StringName(action + "_" + AntAgent.Role.keys()[role].to_lower())
