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
var _choices: ScrollContainer
var _observed_workplace: Workplace

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyStyle.apply(self)
	context = payload as BuildMenuContext
	if context == null or not is_instance_valid(context.controller):
		close_requested.emit.call_deferred(self)
		return
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", ColonyStyle.dialog_box())
	_panel.custom_minimum_size.x = 216
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	_panel.add_child(content)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	content.add_child(heading)
	_title = ColonyStyle.label("")
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	var close: Button = ColonyStyle.button("X")
	close.custom_minimum_size = Vector2(24, 24)
	close.pressed.connect(func(): close_requested.emit(self))
	heading.add_child(close)
	controls[&"close"] = close
	default_focus = close
	_description = ColonyStyle.label("", 8, ColonyStyle.MUTED)
	content.add_child(_description)
	var scroll := ScrollContainer.new()
	_choices = scroll
	scroll.custom_minimum_size = Vector2(200, 128)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 2)
	scroll.add_child(options)
	for option in context.controller.options:
		if option == null:
			continue
		var button := BuildChoiceButton.new()
		button.option = option
		button.art = context.art
		button.pressed.connect(_choose.bind(option))
		button.mouse_entered.connect(_show_help.bind(option))
		button.focus_entered.connect(_show_help.bind(option))
		options.add_child(button)
		_buttons[option] = button
		controls[option.id] = button
	_message = ColonyStyle.label("", 8, ColonyStyle.TEXT)
	_message.add_theme_stylebox_override("normal", ColonyStyle.box())
	_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_message)
	_message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_message.offset_left = 8
	_message.offset_right = -8
	_message.offset_top = -66
	_message.offset_bottom = -34
	_message.hide()
	_demolish = ColonyStyle.button("Снести")
	_demolish.pressed.connect(_on_demolish_pressed)
	content.add_child(_demolish)
	controls[&"demolish"] = _demolish
	_cancel = ColonyStyle.button("Отменить снос")
	_cancel.pressed.connect(_cancel_confirmation)
	_cancel.hide()
	content.add_child(_cancel)
	controls[&"cancel_demolish"] = _cancel
	context.controller.inventory.changed.connect(_refresh)
	context.controller.changed.connect(_refresh)
	context.controller.registry.changed.connect(_refresh)
	context.population.cell_changed.connect(_on_cell_changed)
	_refresh()

func _process(_delta: float) -> void:
	if context != null and _panel != null and visible:
		reposition()

func contains_point(point: Vector2) -> bool:
	return _panel != null and _panel.get_global_rect().has_point(point)

func retarget(cell: Vector2i, anchor: Rect2) -> void:
	context.cell = cell
	context.anchor = anchor
	_cancel_confirmation()

func reposition() -> void:
	var viewport: Vector2 = size
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var anchor: Rect2 = inverse * context.anchor
	var safe := Rect2(8, 60, viewport.x - 16, viewport.y - 132)
	var popup: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = popup
	var candidates: Array[float] = [anchor.end.x + 6, anchor.position.x - popup.x - 6]
	for obstacle in context.obstacles:
		var local: Rect2 = inverse * obstacle
		candidates.append(local.end.x + 6)
		candidates.append(local.position.x - popup.x - 6)
	var y: float = clampf(anchor.position.y, safe.position.y, maxf(safe.position.y, safe.end.y - popup.y))
	for x in candidates:
		var position := Vector2(clampf(x, safe.position.x, maxf(safe.position.x, safe.end.x - popup.x)), y).round()
		var rect := Rect2(position, popup)
		var blocked: bool = rect.intersects(anchor.grow(-1))
		for obstacle in context.obstacles:
			blocked = blocked or rect.intersects(inverse * obstacle)
		if not blocked:
			_panel.position = position
			return
	_panel.position = Vector2(safe.position.x, y)

func _refresh() -> void:
	if not is_instance_valid(context.controller):
		close_requested.emit(self)
		return
	_choices.visible = not _confirming
	_title.text = "%d:%d" % [context.cell.x, context.cell.y]
	var occupant: Building = context.controller.registry.at(context.cell)
	_observe_workplace(occupant as Workplace)
	_description.text = "Строительство"
	if occupant is Workplace:
		_title.text = occupant.display_title()
		_description.text = "Работают+идут: %d+%d/%d" % [occupant.working_count(), occupant.incoming_count(), occupant.work_slots]
	elif occupant != null:
		_description.text = occupant.display_title()
	elif not context.controller.route_service.walkable(context.cell):
		_description.text = "Вода"
	for option in _buttons:
		var button: Button = _buttons[option]
		var result: PlacementCheck = context.controller.check(option, context.cell)
		button.disabled = not result.allowed() or _confirming
		button.tooltip_text = ""
	var demolition: PlacementCheck = context.controller.demolition_check(context.cell)
	_demolish.visible = occupant != null
	_demolish.disabled = not demolition.allowed()
	_demolish.tooltip_text = PlacementMessages.text(demolition.code)
	reposition()

func _observe_workplace(workplace: Workplace) -> void:
	if is_instance_valid(_observed_workplace) and _observed_workplace == workplace:
		return
	if is_instance_valid(_observed_workplace) and _observed_workplace.load_changed.is_connected(_refresh):
		_observed_workplace.load_changed.disconnect(_refresh)
	_observed_workplace = workplace
	if _observed_workplace != null:
		_observed_workplace.load_changed.connect(_refresh)

func _set_message(text: String) -> void:
	_message.text = text
	_message.visible = not text.is_empty()

func _show_help(option: BuildOption) -> void:
	if _confirming or _message == null:
		return
	var result: PlacementCheck = context.controller.check(option, context.cell)
	var help: String = PlacementMessages.text(result.code)
	if result.allowed():
		help = "%s: %s" % [option.display_name, BuildCostText.format(option.costs)]
		if option is SceneBuildOption and option.spawn_count > 0:
			help += ". +%d муравьёв; нужно %d порций." % [option.spawn_count, option.spawn_count]
	_set_message(help)

func _on_cell_changed(old: Vector2i, next: Vector2i) -> void:
	if old == context.cell or next == context.cell:
		_refresh()

func _choose(option: BuildOption) -> void:
	if context.controller.try_build(option, context.cell):
		action_completed.emit("%s: готово" % option.display_name, false)
		close_requested.emit(self)
	else:
		_set_message(PlacementMessages.text(context.controller.last_result.code))
		_refresh()

func _on_demolish_pressed() -> void:
	if not _confirming:
		_confirming = true
		var building: Building = context.controller.registry.at(context.cell)
		_set_message("Жители погибнут: %d. Снести муравейник?" % building.residents.size() if building is House else "Снести здание без возврата ресурсов?")
		_demolish.text = "Да, снести"
		_demolish.add_theme_color_override("font_color", ColonyStyle.DANGER)
		_cancel.show()
		_refresh()
		return
	if context.controller.demolish_at(context.cell):
		action_completed.emit("Здание снесено", false)
		close_requested.emit(self)
	else:
		_set_message(PlacementMessages.text(context.controller.last_result.code))
		_refresh()

func _cancel_confirmation() -> void:
	_confirming = false
	_set_message("")
	_demolish.text = "Снести"
	_demolish.remove_theme_color_override("font_color")
	_cancel.hide()
	_refresh()

func cancel_or_close() -> void:
	if _confirming:
		_cancel_confirmation()
	else:
		close_requested.emit(self)
