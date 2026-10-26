class_name ConstructionMenu
extends MenuBase
## Paused construction editor. The draft owns edits; the controller commits the final plan.
var context: ConstructionContext
var draft := BuildDraft.new()
var controls: Dictionary[StringName, Button] = {}
var panel: PanelContainer
var _cost: Label
var _status: Label
var _hint: Label
var _preview: BuildPreview
var _selected: BuildOption
var _tool: StringName = &"build"
var _pan_mask := MOUSE_BUTTON_MASK_MIDDLE
var _confirmation: HBoxContainer
var _confirm_label: Label
var _painting := false
var _panning := false
var _last_cell := Vector2i.ZERO
var _has_last := false
var _refresh_queued := false

func _ready() -> void:
	dismissable = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyStyle.apply(self)
	context = payload as ConstructionContext
	if context == null or not is_instance_valid(context.controller):
		close_requested.emit.call_deferred(self)
		return
	draft.controller = context.controller
	_preview = BuildPreview.new()
	_preview.draft = draft
	_preview.art = context.art
	_preview.z_index = 3
	context.controller.map.get_parent().add_child(_preview)
	panel = PanelContainer.new()
	panel.set_meta(&"ui_manual_layout", true)
	panel.add_theme_stylebox_override("panel", ColonyStyle.dialog_box())
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_top = -150
	panel.offset_bottom = -6
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	content.add_child(toolbar)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 34
	toolbar.add_child(scroll)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 4)
	scroll.add_child(choices)
	var group := ButtonGroup.new()
	for option in context.controller.options:
		if option == null: continue
		var button := BuildChoiceButton.new()
		button.option = option
		button.art = context.art
		button.card_width = 96
		button.compact = true
		button.tooltip_text = "%s: %s" % [option.display_name, BuildCostText.format(option.costs)]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_select.bind(option))
		choices.add_child(button)
		controls[option.id] = button
		if _selected == null: _select(option)
	for entry in [[&"move", "Перемещение: ЛКМ двигает карту", "move"], [&"demolish", "Снос: отметить здание или дорогу", "demolish"]]:
		var tool: Button = ColonyStyle.button("")
		tool.custom_minimum_size = Vector2(32, 32)
		tool.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tool.icon = load("res://game/assets/ui/build_%s.svg" % entry[2])
		tool.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tool.tooltip_text = entry[1]
		tool.toggle_mode = true
		tool.button_group = group
		tool.pressed.connect(_select_tool.bind(entry[0]))
		toolbar.add_child(tool)
		controls[entry[0]] = tool
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	toolbar.add_child(actions)
	for entry in [[&"undo", "Отменить ход (Ctrl+Z)", "undo", _undo], [&"cancel", "Отменить всё", "cancel", _cancel], [&"apply", "Применить и продолжить (Пробел)", "apply", apply_and_resume]]:
		var button: Button = ColonyStyle.button("", entry[0] == &"apply")
		button.custom_minimum_size = Vector2(32, 32)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.icon = load("res://game/assets/ui/build_%s.svg" % entry[2])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = entry[1]
		button.pressed.connect(entry[3])
		actions.add_child(button)
		controls[entry[0]] = button
	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 8)
	content.add_child(summary)
	_cost = ColonyStyle.label("", 6)
	_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_child(_cost)
	_hint = ColonyStyle.label("", 4, ColonyStyle.MUTED)
	summary.add_child(_hint)
	_status = ColonyStyle.label("", 6, ColonyStyle.DANGER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.hide()
	content.add_child(_status)
	_confirmation = HBoxContainer.new()
	_confirmation.add_theme_constant_override("separation", 4)
	_confirm_label = ColonyStyle.label("", 6, ColonyStyle.DANGER)
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirmation.add_child(_confirm_label)
	for entry in [[&"confirm_demolish", "Да, снести", _commit], [&"keep_residents", "Назад", _cancel_confirmation]]:
		var button: Button = ColonyStyle.button(entry[1])
		button.pressed.connect(entry[2])
		_confirmation.add_child(button)
		controls[entry[0]] = button
	content.add_child(_confirmation)
	_confirmation.hide()
	draft.changed.connect(_cancel_confirmation)
	draft.changed.connect(_queue_refresh)
	_refresh()
	default_focus = controls[_selected.id] if _selected != null else controls[&"cancel"]

func _exit_tree() -> void:
	if is_instance_valid(_preview): _preview.queue_free()

func _select(option: BuildOption) -> void:
	_end_stroke()
	_tool = &"build"
	_selected = option
	_preview.demolishing = false
	controls[option.id].set_pressed_no_signal(true)
	_preview.option = option
	_preview.queue_redraw()
	if _hint != null: _refresh()

func _select_tool(tool: StringName) -> void:
	_end_stroke()
	_tool = tool
	controls[tool].set_pressed_no_signal(true)
	_preview.option = null
	_preview.demolishing = tool == &"demolish"
	_preview.queue_redraw()
	_refresh()

func _cancel_confirmation() -> void:
	if _confirmation != null: _confirmation.hide()

func _refresh() -> void:
	_refresh_queued = false
	_hint.text = "ЛКМ: строить · ПКМ: убрать слой" if _tool == &"build" else ("ЛКМ/СКМ: камера · колесо: зум" if _tool == &"move" else "ЛКМ: снос · ПКМ: убрать отметку")
	var budget: PlacementCheck = draft.budget_check()
	_cost.text = "План: %d · %s" % [draft.size(), BuildCostText.format(draft.costs())]
	_cost.add_theme_color_override("font_color", ColonyStyle.TEXT if budget.allowed() else ColonyStyle.DANGER)
	controls[&"undo"].disabled = not draft.can_undo()
	controls[&"apply"].disabled = not budget.allowed()
	var reason: PlacementCheck = budget if not budget.allowed() else draft.last_result
	_status.text = PlacementMessages.text(reason.code)
	_status.visible = not reason.allowed()
	_status.add_theme_color_override("font_color", ColonyStyle.DANGER if not reason.allowed() else ColonyStyle.MUTED)
	_preview.queue_redraw()

func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	_refresh.call_deferred()

func _undo() -> void:
	_end_stroke()
	draft.undo()

func _cancel() -> void:
	_end_stroke()
	draft.clear()
	close_requested.emit(self)

func apply_and_resume() -> void:
	_end_stroke()
	var residents: int = draft.residents_to_demolish()
	if residents > 0:
		_confirm_label.text = "Жители погибнут: %d. Снести муравейник?" % residents
		_confirmation.show()
		return
	_commit()

func _commit() -> void:
	if draft.commit():
		close_requested.emit(self)

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Z and event.ctrl_pressed:
		_undo()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_B, KEY_SPACE]:
		apply_and_resume()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_end_stroke()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
		if (event.button_mask & _pan_mask) == 0: _panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			if event.button_mask & _pan_mask:
				context.camera.pan(event.relative)
			else:
				_panning = false
			get_viewport().set_input_as_handled()
		elif _painting:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_paint_to(event.position)
			else:
				_end_stroke()
			get_viewport().set_input_as_handled()
		_update_hover(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventMouseButton and event.pressed and _point_allowed(event.position):
		if event.button_index == MOUSE_BUTTON_LEFT and _tool == &"move":
			_end_stroke()
			_panning = true
			_pan_mask = MOUSE_BUTTON_MASK_LEFT
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			draft.begin_stroke()
			_painting = true
			_has_last = false
			_paint_to(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_end_stroke()
			_panning = true
			_pan_mask = MOUSE_BUTTON_MASK_MIDDLE
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_end_stroke()
			draft.begin_stroke()
			draft.remove_last(_cell(event.position))
			draft.end_stroke()
			_refresh()
			get_viewport().set_input_as_handled()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_end_stroke()
			context.camera.set_level(context.camera.level + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			get_viewport().set_input_as_handled()

func _point_allowed(point: Vector2) -> bool:
	if point.y < 60 * AppSettings.ui_scale or point.y >= panel.get_global_rect().position.y or not get_viewport_rect().has_point(point): return false
	for obstacle in context.obstacles:
		if obstacle.has_point(point): return false
	return true

func _cell(point: Vector2) -> Vector2i:
	var map: TileMapLayer = context.controller.map
	return map.local_to_map(map.get_global_transform_with_canvas().affine_inverse() * point)

func _paint_to(point: Vector2) -> void:
	if not _point_allowed(point):
		_has_last = false
		return
	var target: Vector2i = _cell(point)
	if _has_last:
		var distance: Vector2i = (target - _last_cell).abs()
		var steps: int = maxi(distance.x, distance.y)
		var previous: Vector2i = _last_cell
		for index in range(1, steps + 1):
			var cell: Vector2i = Vector2i(Vector2(_last_cell).lerp(Vector2(target), float(index) / steps).round())
			if cell.x != previous.x and cell.y != previous.y:
				_paint_cell(Vector2i(cell.x, previous.y))
			_paint_cell(cell)
			previous = cell
	else:
		_paint_cell(target)
	_last_cell = target
	_has_last = true
	_refresh()

func _paint_cell(cell: Vector2i) -> void:
	if _tool == &"demolish": draft.demolish(cell)
	elif _tool == &"build": draft.paint(_selected, cell)

func _end_stroke() -> void:
	_painting = false
	_has_last = false
	draft.end_stroke()
	if _cost != null: _refresh()

func _update_hover(point: Vector2) -> void:
	var hovering: bool = _point_allowed(point)
	var cell: Vector2i = _cell(point)
	if _preview.hovering != hovering or _preview.hover != cell:
		_preview.hovering = hovering
		_preview.hover = cell
		_preview.queue_redraw()

func _process(delta: float) -> void:
	if not visible: return
	panel.offset_left = roundf(8 * AppSettings.ui_scale)
	panel.offset_right = -roundf(8 * AppSettings.ui_scale)
	panel.offset_bottom = -roundf(6 * AppSettings.ui_scale)
	panel.offset_top = -panel.get_combined_minimum_size().y - roundf(6 * AppSettings.ui_scale)
	if not _painting:
		var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if not direction.is_zero_approx():
			context.camera.pan(-direction.normalized() * delta * 100.0)
	_update_hover(get_viewport().get_mouse_position())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_stroke()
		_panning = false
