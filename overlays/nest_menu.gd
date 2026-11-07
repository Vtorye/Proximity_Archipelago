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
var _dispatch: CheckButton
var _dispatch_hint: Label

func _ready() -> void:
	if not payload is Dictionary:
		close_requested.emit.call_deferred(self)
		return
	world = payload.get("world") as World
	house = payload.get("house") as House
	if not is_instance_valid(world) or not world.logistics.owns(house):
		close_requested.emit.call_deferred(self)
		return
	var content: VBoxContainer = ColonyStyle.modal(self, 224)
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
	for key in [&"inventory", &"residents"]:
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
	_dispatch = CheckButton.new()
	_dispatch.text = "ui.storage.auto"
	_dispatch.toggled.connect(func(enabled: bool):
		if is_instance_valid(house): house.auto_dispatch = enabled)
	_inventory_tab.add_child(_dispatch)
	_dispatch_hint = ColonyStyle.label("ui.nest.dispatch_hint", 4, ColonyStyle.MUTED)
	_dispatch_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_tab.add_child(_dispatch_hint)
	_residents_tab = VBoxContainer.new()
	_residents_tab.add_theme_constant_override("separation", 8)
	content.add_child(_residents_tab)
	_population = ColonyStyle.label("", 8, ColonyStyle.ACCENT)
	_residents_tab.add_child(_population)
	for role in [AntAgent.Role.WORKER, AntAgent.Role.CARRIER]:
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
		labels.add_child(price)
		_purchase_labels[role] = price
		var buy: Button = ColonyStyle.button("ui.nest.buy")
		buy.pressed.connect(_recruit.bind(role))
		line.add_child(buy)
		controls[&"buy_worker" if role == AntAgent.Role.WORKER else &"buy_carrier"] = buy
		var kill: Button = ColonyStyle.button("ui.nest.kill")
		kill.add_theme_color_override("font_color", ColonyStyle.DANGER)
		kill.tooltip_text = "ui.nest.kill_hint"
		kill.pressed.connect(_kill.bind(role))
		line.add_child(kill)
		controls[&"kill_worker" if role == AntAgent.Role.WORKER else &"kill_carrier"] = kill
	_residents_tab.add_child(ColonyStyle.label("ui.nest.assigned", 4, ColonyStyle.MUTED))
	world.inventory.changed.connect(refresh)
	world.population.changed.connect(refresh)
	house.tree_exiting.connect(func(): close_requested.emit(self))
	_show_tab(&"inventory")
	refresh()
	default_focus = close

func _show_tab(key: StringName) -> void:
	_inventory_tab.visible = key == &"inventory"
	_residents_tab.visible = key == &"residents"
	controls[key].set_pressed_no_signal(true)

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
	_capacity.text = tr("ui.nest.unlimited") if main else tr("ui.storage.fill") % [world.inventory.depot_fill(house), house.storage_capacity]
	for type in world.inventory.registered_types():
		var amount: int = world.inventory.main_quantity(type) if main else world.inventory.depot_quantity(house, type)
		_stock_labels[type.id].text = "%s · %d" % [tr(type.display_name), amount]
	_dispatch.visible = not main
	_dispatch_hint.visible = not main
	_dispatch.set_pressed_no_signal(house.auto_dispatch)
	_population.text = tr("ui.nest.population") % [house.residents.size(), house.resident_limit()]
	var counts := {AntAgent.Role.WORKER: 0, AntAgent.Role.CARRIER: 0}
	for ant: AntAgent in house.residents:
		counts[ant.role] += 1
	for role in counts:
		var title: String = tr("ui.nest.worker" if role == AntAgent.Role.WORKER else "ui.nest.carrier")
		_role_labels[role].text = "%s · %d" % [title, counts[role]]
		controls[&"kill_worker" if role == AntAgent.Role.WORKER else &"kill_carrier"].disabled = counts[role] == 0
		var buy: Button = controls[&"buy_worker" if role == AntAgent.Role.WORKER else &"buy_carrier"]
		buy.disabled = not world.population.can_recruit(house, role)
		_purchase_labels[role].text = BuildCostText.format(world.recruitment.price(role)) if world.recruitment != null else "—"
		buy.tooltip_text = "ui.nest.full" if not house.has_space() else ("ui.nest.unaffordable" if buy.disabled else "ui.nest.from_main")
