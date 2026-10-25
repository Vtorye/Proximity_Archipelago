class_name BuildMenu
extends MenuBase
## Presentation only: the world controller owns validation and construction.
signal action_completed(message: String, danger: bool)
var context: BuildMenuContext
var controls: Dictionary[StringName, Button] = {}
var _buttons: Dictionary[BuildOption, Button] = {}
var _panel: PanelContainer
var _title: Label
var _description: Label
var _message: Label
var _demolish: Button
var _cancel: Button
var _confirming := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyStyle.apply(self)
	context = payload as BuildMenuContext
	if context == null or not is_instance_valid(context.controller):
		close_requested.emit.call_deferred(self)
		return
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 286
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_panel.add_child(content)
	content.add_child(ColonyStyle.label("СТРОИТЕЛЬСТВО", 11, ColonyStyle.ACCENT))
	_title = ColonyStyle.label("", 21)
	content.add_child(_title)
	_description = ColonyStyle.label("", 13, ColonyStyle.MUTED)
	content.add_child(_description)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(256, 278)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 6)
	scroll.add_child(options)
	for option in context.controller.options:
		if option == null:
			continue
		var button: Button = ColonyStyle.button("")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		button.custom_minimum_size.y = 50
		button.icon = _icon(option.id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
		button.add_theme_constant_override("h_separation", 12)
		button.pressed.connect(_choose.bind(option))
		options.add_child(button)
		_buttons[option] = button
		controls[option.id] = button
	_message = ColonyStyle.label("", 13, ColonyStyle.DANGER)
	_message.custom_minimum_size.x = 250
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_message)
	_demolish = ColonyStyle.button("Снести здание")
	_demolish.pressed.connect(_on_demolish_pressed)
	content.add_child(_demolish)
	controls[&"demolish"] = _demolish
	_cancel = ColonyStyle.button("Отменить снос")
	_cancel.pressed.connect(_cancel_confirmation)
	_cancel.hide()
	content.add_child(_cancel)
	controls[&"cancel_demolish"] = _cancel
	var close: Button = ColonyStyle.button("Закрыть · Esc")
	close.pressed.connect(func(): close_requested.emit(self))
	content.add_child(close)
	controls[&"close"] = close
	default_focus = close
	context.controller.inventory.changed.connect(_refresh)
	context.controller.changed.connect(_refresh)
	context.controller.registry.changed.connect(_refresh)
	context.population.cell_changed.connect(_on_cell_changed)
	_refresh()

func _process(_delta: float) -> void:
	if context != null and _panel != null and visible:
		reposition()

func reposition() -> void:
	var viewport: Vector2 = get_viewport_rect().size
	var safe := Rect2(16, 110, viewport.x - 32, viewport.y - 176)
	var popup: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = popup
	var x: float = context.anchor.end.x + 12
	if x + popup.x > safe.end.x:
		x = context.anchor.position.x - popup.x - 12
	_panel.position = Vector2(clampf(x, safe.position.x, maxf(safe.position.x, safe.end.x - popup.x)), clampf(context.anchor.position.y, safe.position.y, maxf(safe.position.y, safe.end.y - popup.y)))

func _icon(id: StringName) -> Texture2D:
	match id:
		&"road": return context.art.road
		&"ground": return context.art.soil
		&"house": return context.art.nest
		&"apple_tree": return context.art.berries
	return context.art.stone

func _refresh() -> void:
	if not is_instance_valid(context.controller):
		close_requested.emit(self)
		return
	_title.text = "Клетка %d · %d" % [context.cell.x, context.cell.y]
	var occupant: Building = context.controller.registry.at(context.cell)
	_description.text = "Выберите постройку или покрытие"
	if occupant != null:
		_description.text = "Здание: %s" % occupant.display_title()
	elif not context.controller.route_service.walkable(context.cell):
		_description.text = "Вода · строительство недоступно"
	for option in _buttons:
		var button: Button = _buttons[option]
		var cost: ResourceAmount = option.cost
		button.text = "%s\n%s: %d" % [option.display_name, cost.type.display_name, cost.amount] if cost != null and cost.type != null else option.display_name
		var result: PlacementCheck = context.controller.check(option, context.cell)
		button.disabled = not result.allowed() or _confirming
		button.tooltip_text = PlacementMessages.text(result.code)
	var demolition: PlacementCheck = context.controller.demolition_check(context.cell)
	_demolish.disabled = not demolition.allowed()
	_demolish.tooltip_text = PlacementMessages.text(demolition.code)
	reposition()

func _on_cell_changed(old: Vector2i, next: Vector2i) -> void:
	if old == context.cell or next == context.cell:
		_refresh()

func _choose(option: BuildOption) -> void:
	if context.controller.try_build(option, context.cell):
		action_completed.emit("%s: готово" % option.display_name, false)
		close_requested.emit(self)
	else:
		_message.text = PlacementMessages.text(context.controller.last_result.code)
		_refresh()

func _on_demolish_pressed() -> void:
	if not _confirming:
		_confirming = true
		var building: Building = context.controller.registry.at(context.cell)
		_message.text = "Жители погибнут: %d. Снести муравейник?" % building.residents.size() if building is House else "Снести это здание? Ресурсы не возвращаются."
		_demolish.text = "Да, снести"
		_demolish.add_theme_color_override("font_color", ColonyStyle.DANGER)
		_cancel.show()
		_refresh()
		return
	if context.controller.demolish_at(context.cell):
		action_completed.emit("Здание снесено", false)
		close_requested.emit(self)
	else:
		_message.text = PlacementMessages.text(context.controller.last_result.code)
		_refresh()

func _cancel_confirmation() -> void:
	_confirming = false
	_message.text = ""
	_demolish.text = "Снести здание"
	_demolish.remove_theme_color_override("font_color")
	_cancel.hide()
	_refresh()

func cancel_or_close() -> void:
	if _confirming:
		_cancel_confirmation()
	else:
		close_requested.emit(self)
