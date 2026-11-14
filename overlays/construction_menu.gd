class_name ConstructionMenu
extends MenuBase
## Paused construction editor. The draft owns edits; the controller commits the final plan.
signal map_inspection_requested(cell: Vector2i)

var context: ConstructionContext
var draft := BuildDraft.new()
var controls: Dictionary[StringName, Button] = {}
@onready var panel: PanelContainer = %Panel
@onready var _cost: Label = %Cost
@onready var _status: Label = %Status
@onready var _hint: Label = %Hint
var _preview: BuildPreview
var _selected: BuildOption
var _tool: StringName = &"build"
var _pan_mask := MOUSE_BUTTON_MASK_MIDDLE
@onready var _confirmation: HBoxContainer = %Confirmation
@onready var _confirm_label: Label = %ConfirmLabel
var _painting := false
var _panning := false
var _pan_moved := false
var _last_cell := Vector2i.ZERO
var _has_last := false
var _refresh_queued := false
var _pointer := Vector2.ZERO
var _pricing_cell := Vector2i(2147483647, 2147483647)

func _ready() -> void:
	_pointer = get_viewport().get_mouse_position()
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
	var choices: HBoxContainer = %Choices
	var group: ButtonGroup = %Move.button_group
	for option in context.controller.options:
		if option == null: continue
		var button: BuildChoiceButton = preload("res://game/ui/build_choice_button.tscn").instantiate()
		button.controller = context.controller
		button.option = option
		button.art = context.art
		button.card_width = 96
		button.compact = true
		button.tooltip_text = "%s: %s" % [tr(option.display_name), BuildCostText.format(context.controller.price(option))]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_select.bind(option))
		choices.add_child(button)
		controls[option.id] = button
	controls[&"move"] = %Move
	%Move.pressed.connect(AppSettings.play_click)
	%Move.pressed.connect(_select_tool.bind(&"move"))
	controls[&"demolish"] = %Demolish
	%Demolish.pressed.connect(AppSettings.play_click)
	%Demolish.pressed.connect(_select_tool.bind(&"demolish"))
	controls[&"undo"] = %Undo
	%Undo.pressed.connect(AppSettings.play_click)
	%Undo.pressed.connect(_undo)
	controls[&"cancel"] = %Cancel
	%Cancel.pressed.connect(AppSettings.play_click)
	%Cancel.pressed.connect(_cancel)
	controls[&"apply"] = %Apply
	%Apply.pressed.connect(AppSettings.play_click)
	%Apply.pressed.connect(apply_and_resume)
	controls[&"confirm_demolish"] = %Confirm
	%Confirm.pressed.connect(AppSettings.play_click)
	%Confirm.pressed.connect(_commit)
	controls[&"keep_residents"] = %KeepResidents
	%KeepResidents.pressed.connect(AppSettings.play_click)
	%KeepResidents.pressed.connect(_cancel_confirmation)
	if choices.get_child_count() > 0:
		var first: BuildChoiceButton = choices.get_child(0)
		_select(first.option)
	draft.changed.connect(_cancel_confirmation)
	if context.controller.prices != null: context.controller.prices.changed.connect(func():
		draft.last_result = PlacementCheck.new()
		_queue_refresh())
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
	_hint.text = "ui.construction.build_hint" if _tool == &"build" else ("ui.construction.inspect_hint" if _tool == &"move" else "ui.construction.demolish_hint")
	if context.controller.terrain != null:
		var soil: TerrainType = context.controller.terrain.map.ground_at(_pricing_cell)
		if soil != null: _hint.text = tr(soil.display_name)
	var budget: PlacementCheck = draft.budget_check()
	_cost.text = tr("ui.construction.cost") % [draft.size(), BuildCostText.format(draft.costs())]
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
		_confirm_label.text = tr("ui.build.confirm_residents") % residents
		_confirmation.show()
		return
	_commit()

func _commit() -> void:
	if draft.commit():
		close_requested.emit(self)

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventMouseMotion or event is InputEventMouseButton: _pointer = event.position
	if event is InputEventKey and event.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Z and event.ctrl_pressed:
		_undo()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_B, KEY_SPACE]:
		apply_and_resume()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_end_stroke()
			if _panning and _pan_mask == MOUSE_BUTTON_MASK_LEFT and not _pan_moved and _point_allowed(event.position):
				_panning = false
				map_inspection_requested.emit(_cell(event.position))
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
		if (event.button_mask & _pan_mask) == 0: _panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			if event.button_mask & _pan_mask:
				_pan_moved = _pan_moved or not event.relative.is_zero_approx()
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
			_pan_moved = false
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
			var cell: Vector2i = _cell(event.position)
			var removed: bool = draft.remove_last(cell)
			draft.end_stroke()
			if not removed:
				map_inspection_requested.emit(cell)
			_refresh()
			get_viewport().set_input_as_handled()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_end_stroke()
			context.camera.set_level(context.camera.level + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			get_viewport().set_input_as_handled()

func _point_allowed(point: Vector2) -> bool:
	if point.y < 60 * AppSettings.ui_scale or point.y >= panel.get_global_rect().position.y or not get_viewport_rect().has_point(point): return false
	for obstacle: Rect2 in context.obstacles.call():
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
		if hovering:
			_pricing_cell = cell
			for control in controls.values():
				if control is BuildChoiceButton: control.set_pricing_cell(cell)
		_queue_refresh()
		_preview.queue_redraw()

func _process(delta: float) -> void:
	if not visible: return
	panel.offset_left = roundf(8 * AppSettings.ui_scale)
	panel.offset_right = -roundf(8 * AppSettings.ui_scale)
	panel.offset_bottom = -roundf(6 * AppSettings.ui_scale)
	panel.offset_top = -panel.get_combined_minimum_size().y - roundf(6 * AppSettings.ui_scale)
	if not _painting:
		var direction: Vector2 = WorldCamera.keyboard_direction()
		if not direction.is_zero_approx():
			context.camera.pan(-direction.normalized() * delta * 100.0)
	_update_hover(_pointer)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_stroke()
		_panning = false
