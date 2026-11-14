class_name NestMenu
extends MenuBase
## Per-nest inventory, assigned residents, and recruitment.

var world: World
var house: House
var controls: Dictionary[StringName, Button] = {}
var _inventory_tab: VBoxContainer
var _residents_tab: VBoxContainer
var _stock_labels: Dictionary[StringName, Label] = {}
var _role_labels: Dictionary[int, Label] = {}
var _purchase_labels: Dictionary[int, Label] = {}
var _population: Label
var _capacity: Label
var _orders_tab: VBoxContainer
var _order_rows: Dictionary[String, Dictionary] = {}
var _funds: CheckButton

func _ready() -> void:
	if not payload is Dictionary:
		close_requested.emit.call_deferred(self)
		return
	world = payload.get("world") as World
	house = payload.get("house") as House
	if not is_instance_valid(world) or not world.logistics.owns(house):
		close_requested.emit.call_deferred(self)
		return
	var content: VBoxContainer = ColonyStyle.modal(self, 240 if world.combat != null else 224)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title: Label = ColonyStyle.label("ui.storage.main" if house.is_main_nest else "ui.storage.local", 12, ColonyStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = ColonyStyle.button("ui.common.back")
	close.pressed.connect(func(): close_requested.emit(self))
	header.add_child(close)
	controls[&"close"] = close
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	var group := ButtonGroup.new()
	for key in [&"inventory", &"orders", &"residents"]:
		var button: Button = ColonyStyle.button("ui.nest." + str(key))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_tab.bind(key))
		tabs.add_child(button)
		controls[key] = button
	_inventory_tab = VBoxContainer.new()
	_inventory_tab.add_theme_constant_override("separation", 6)
	content.add_child(_inventory_tab)
	_capacity = ColonyStyle.label("")
	_inventory_tab.add_child(_capacity)
	for type in world.inventory.registered_types():
		var line: Label = ColonyStyle.label("")
		_stock_labels[type.id] = line
		_inventory_tab.add_child(line)
	_orders_tab = VBoxContainer.new()
	_orders_tab.add_theme_constant_override("separation", 6)
	content.add_child(_orders_tab)
	_funds = CheckButton.new()
	_funds.text = "ui.nest.funds_construction"
	_funds.toggled.connect(func(enabled: bool):
		if is_instance_valid(house): house.funds_construction = enabled)
	_orders_tab.add_child(_funds)
	# One grid for the header and every row keeps the four columns aligned:
	# name | min | max | owed.
	var order_grid := GridContainer.new()
	order_grid.columns = 4
	order_grid.add_theme_constant_override("h_separation", 6)
	order_grid.add_theme_constant_override("v_separation", 6)
	_orders_tab.add_child(order_grid)
	order_grid.add_child(ColonyStyle.label(""))
	for key in ["ui.order.min", "ui.order.max", "ui.order.once"]:
		var caption: Label = ColonyStyle.label(key, 4, ColonyStyle.MUTED)
		caption.custom_minimum_size.x = 72
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		order_grid.add_child(caption)
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
	_residents_tab = VBoxContainer.new()
	_residents_tab.add_theme_constant_override("separation", 8)
	content.add_child(_residents_tab)
	_population = ColonyStyle.label("", 8, ColonyStyle.ACCENT)
	_residents_tab.add_child(_population)
	for role in world.population.roles():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		_residents_tab.add_child(line)
		var labels := VBoxContainer.new()
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(labels)
		var count: Label = ColonyStyle.label("")
		labels.add_child(count)
		_role_labels[role] = count
		var price: Label = ColonyStyle.label("", 4, ColonyStyle.MUTED)
		price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		price.custom_minimum_size.x = 104
		labels.add_child(price)
		_purchase_labels[role] = price
		var buy: Button = ColonyStyle.button("ui.nest.buy")
		buy.pressed.connect(_recruit.bind(role))
		line.add_child(buy)
		controls[_control_key("buy", role)] = buy
		var kill: Button = ColonyStyle.button("ui.nest.kill")
		kill.add_theme_color_override("font_color", ColonyStyle.DANGER)
		kill.tooltip_text = "ui.nest.kill_hint"
		kill.pressed.connect(_kill.bind(role))
		line.add_child(kill)
		controls[_control_key("kill", role)] = kill
	_residents_tab.add_child(ColonyStyle.label("ui.nest.assigned", 4, ColonyStyle.MUTED))
	world.inventory.changed.connect(refresh)
	world.population.changed.connect(refresh)
	house.tree_exiting.connect(func(): close_requested.emit(self))
	_show_tab(&"inventory")
	refresh()
	default_focus = close

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
