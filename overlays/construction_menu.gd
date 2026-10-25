class_name ConstructionMenu
extends MenuBase
## Paused construction editor. The draft owns edits; the controller commits the final plan.
var context: ConstructionContext
var draft := BuildDraft.new()
var controls: Dictionary[StringName, Button] = {}
var panel: PanelContainer
var _cost: Label
var _status: Label
var _preview: BuildPreview
var _selected: BuildOption
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
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	content.add_child(title)
	title.add_child(ColonyStyle.label("Стройка · пауза", 8, ColonyStyle.ACCENT))
	var hints: Label = ColonyStyle.label("ЛКМ: рисовать  СКМ/WASD: камера", 6, ColonyStyle.MUTED)
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.add_child(hints)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 54
	content.add_child(scroll)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 4)
	scroll.add_child(choices)
	var group := ButtonGroup.new()
	for option in context.controller.options:
		if option == null: continue
		var button := BuildChoiceButton.new()
		button.option = option
		button.art = context.art
		button.card_width = 144
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_select.bind(option))
		choices.add_child(button)
		controls[option.id] = button
		if _selected == null: _select(option)
	_cost = ColonyStyle.label("", 6)
	_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_cost)
	_status = ColonyStyle.label("", 6, ColonyStyle.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	content.add_child(actions)
	for entry in [[&"undo", "Отменить ход", _undo], [&"cancel", "Отменить всё", _cancel], [&"apply", "Продолжить", apply_and_resume]]:
		var button: Button = ColonyStyle.button(entry[1], entry[0] == &"apply")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[2])
		actions.add_child(button)
		controls[entry[0]] = button
	draft.changed.connect(_queue_refresh)
	_refresh()
	default_focus = controls[_selected.id] if _selected != null else controls[&"cancel"]

func _exit_tree() -> void:
	if is_instance_valid(_preview): _preview.queue_free()

func _select(option: BuildOption) -> void:
	_end_stroke()
	_selected = option
	controls[option.id].set_pressed_no_signal(true)
	_preview.option = option
	_preview.queue_redraw()

func _refresh() -> void:
	_refresh_queued = false
	var budget: PlacementCheck = draft.budget_check()
	_cost.text = "План: %d · %s" % [draft.size(), BuildCostText.format(draft.costs())]
	_cost.add_theme_color_override("font_color", ColonyStyle.TEXT if budget.allowed() else ColonyStyle.DANGER)
	controls[&"undo"].disabled = not draft.can_undo()
	controls[&"apply"].disabled = not budget.allowed()
	var reason: PlacementCheck = budget if not budget.allowed() else draft.last_result
	_status.text = PlacementMessages.text(reason.code) if not reason.allowed() else "Ресурсы спишутся при продолжении. Esc: применить план."
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
	if draft.commit():
		close_requested.emit(self)

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_B]:
		apply_and_resume()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_end_stroke()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			draft.begin_stroke()
			_painting = true
			_has_last = false
			_paint_to(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_end_stroke()
			_panning = true
			get_viewport().set_input_as_handled()
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			get_viewport().set_input_as_handled()

func _point_allowed(point: Vector2) -> bool:
	if point.y < 60 or point.y >= panel.position.y or not get_viewport_rect().has_point(point): return false
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
				draft.paint(_selected, Vector2i(cell.x, previous.y))
			draft.paint(_selected, cell)
			previous = cell
	else:
		draft.paint(_selected, target)
	_last_cell = target
	_has_last = true
	_refresh()

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
	panel.offset_top = -panel.get_combined_minimum_size().y - 6
	if not _painting:
		var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if not direction.is_zero_approx():
			context.camera.pan(-direction.normalized() * delta * 100.0)
	_update_hover(get_viewport().get_mouse_position())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_stroke()
		_panning = false
