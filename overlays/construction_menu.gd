class_name ConstructionMenu
extends MenuBase

const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")
## Construction editor. The draft owns edits; the controller commits the final plan.
signal map_drag_released
signal map_inspection_requested(cell: Vector2i)
signal order_placement_finished

var context: ConstructionContext
var draft := BuildDraft.new()
var controls: Dictionary[StringName, Button] = {}
@onready var panel: PanelContainer = %Panel
@onready var _header: WindowHeader = %PaletteHeader
@onready var _cost: Label = %Cost
@onready var _status: Label = %Status
@onready var _hint: Label = %Hint
var _preview: BuildPreview
var _selected: BuildOption
var _map_drag := false
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
var category_buttons: Array[Button] = []
var _category_for: Dictionary[StringName, Button] = {}

var _pricing_cell := Vector2i(2147483647, 2147483647)
var order_mode := false

func toggle_fold() -> void:
	_header.set_collapsed(not _header.collapsed)

func dock_above(bar_height: float) -> void:
	_header.inset.y = bar_height + PRESENTATION.dock_clearance
	_header.queue_layout()

func _ready() -> void:
	%PreviewCategory.hide()
	%PreviewCard.hide()
	%Toolbar.move_child(%Demolish, %Toolbar.get_child_count() - 1)
	%Actions.move_child(%Cancel, %Actions.get_child_count() - 1)
	%PaletteHeader.collapsed_changed.connect(func(_folded: bool): _end_stroke())
	_pointer = get_viewport().get_mouse_position()
	dismissable = false
	visibility_changed.connect(_on_visibility_changed)
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
	%Apply.pressed.connect(apply_plan)
	controls[&"confirm_demolish"] = %Confirm
	%Confirm.pressed.connect(AppSettings.play_click)
	%Confirm.pressed.connect(_commit)
	controls[&"keep_residents"] = %KeepResidents
	%KeepResidents.pressed.connect(AppSettings.play_click)
	%KeepResidents.pressed.connect(_cancel_confirmation)
	_populate_categories()
	if not context.controller.options.is_empty() and context.controller.options[0] != null:
		var first: BuildOption = context.controller.options[0]
		show_category_for(first.id)
		_select(first)
	draft.changed.connect(_cancel_confirmation)
	if context.controller.prices != null: context.controller.prices.changed.connect(func():
		draft.last_result = PlacementCheck.new()
		_queue_refresh())
	context.controller.inventory.changed.connect(_queue_refresh)
	context.controller.registry.removed.connect(draft.forget_removal)
	context.controller.registry.changed.connect(_queue_refresh)
	AppSettings.changed.connect(_queue_refresh)
	draft.changed.connect(_queue_refresh)
	_refresh()
	default_focus = controls[_selected.id] if _selected != null else controls[&"cancel"]

func _populate_categories() -> void:
	var remaining: Array[BuildOption] = context.controller.options.duplicate()
	var catalog: BuildCatalog = context.controller.catalog
	if catalog != null:
		for category in catalog.categories:
			if category == null:
				continue
			var available: Array[BuildOption] = []
			for definition in category.options:
				if definition == null:
					continue
				for option in remaining:
					if option != null and option.id == definition.id:
						available.append(option)
						remaining.erase(option)
						break
			_add_category(category.title, available)
	remaining = remaining.filter(func(option: BuildOption) -> bool: return option != null)
	_add_category("ui.construction.category.other", remaining)

func _add_category(title: String, options: Array[BuildOption]) -> void:
	if options.is_empty():
		return
	var category: Button = preload("res://game/ui/palette_entry.tscn").instantiate()
	category.text = title
	category.tooltip_text = title
	category.toggle_mode = true
	category.pressed.connect(AppSettings.play_click)
	category.pressed.connect(_show_category.bind(category))
	%CategoryList.add_child(category)
	category_buttons.append(category)
	for option in options:
		var entry: ConstructionCard = preload("res://game/ui/construction_card.tscn").instantiate()
		entry.button_group = %Demolish.button_group
		entry.pressed.connect(AppSettings.play_click)
		entry.pressed.connect(_select.bind(option))
		%Choices.add_child(entry)
		entry.configure(option, context.art)
		controls[option.id] = entry
		_category_for[option.id] = category
		entry.hide()

func show_category_for(option_id: StringName) -> void:
	var category: Button = _category_for.get(option_id)
	if category != null:
		_show_category(category)

func _show_category(category: Button) -> void:
	%Buildings.scroll_vertical = 0
	for button in category_buttons:
		button.set_pressed_no_signal(button == category)
	for id in _category_for:
		controls[id].visible = _category_for[id] == category

func _update_details() -> void:
	var option: BuildOption = _selected if _tool == &"build" else null
	%BuildingName.text = option.display_name if option != null else ""
	%Description.text = option.description if option != null else "ui.construction.empty"
	%Parameters.text = ""
	%Price.text = ""
	if option == null:
		return
	var price: Array[ResourceAmount] = context.controller.price(option, _pricing_cell)
	%Price.text = tr("ui.construction.price") % BuildCostText.format(price)
	var parameters := PackedStringArray()
	if context.controller.construction != null and ConstructionService.needs_builders(option, price):
		parameters.append(tr("ui.construction.time") % str(option.construction_seconds))
	else:
		parameters.append(tr("ui.construction.instant"))
	if option is SceneBuildOption:
		parameters.append(tr("ui.construction.footprint") % option.occupied_cells.size())
		if option.requires_water:
			parameters.append(tr("ui.construction.water"))
	elif option is WorkplaceUpgradeOption:
		parameters.append(tr("ui.construction.slots") % option.added_slots)
	elif option is TileBuildOption:
		var map := context.controller.map as TerrainMap
		if map != null:
			var terrain: TerrainType = map.catalog.for_tile(Vector4i(option.source_id, option.atlas_coords.x, option.atlas_coords.y, option.alternative_tile))
			if terrain != null:
				parameters.append(tr("ui.construction.speed") % str(terrain.move_cost))
	%Parameters.text = "\n".join(parameters)

func _on_visibility_changed() -> void:
	if is_instance_valid(_preview):
		_preview.visible = visible
	if not visible and context != null:
		_end_stroke()
		_panning = false
		_preview.hovering = false
		_preview.queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(_preview): _preview.queue_free()

func _select(option: BuildOption) -> void:
	if _map_drag: map_drag_released.emit()
	_end_stroke()
	_tool = &"build"
	_selected = option
	%DescriptionScroll.scroll_vertical = 0
	_preview.demolishing = false
	controls[option.id].set_pressed_no_signal(true)
	_preview.option = option
	_preview.queue_redraw()
	_refresh()

func select_option(option: BuildOption) -> void:
	if option == null: return
	if not controls.has(option.id):
		context.controller.options.append(option)
		var entry: ConstructionCard = preload("res://game/ui/construction_card.tscn").instantiate()
		entry.button_group = %Demolish.button_group
		entry.pressed.connect(AppSettings.play_click)
		entry.pressed.connect(_select.bind(option))
		%Choices.add_child(entry)
		entry.configure(option, context.art)
		controls[option.id] = entry
		_category_for[option.id] = category_buttons[0] if not category_buttons.is_empty() else null
		entry.show()
	show_category_for(option.id)
	_select(option)

func set_map_drag(enabled: bool) -> void:
	_end_stroke()
	_panning = false
	_map_drag = enabled
	_preview.option = _selected if not enabled and _tool == &"build" else null
	_preview.demolishing = not enabled and _tool == &"demolish"
	_refresh()

func _select_tool(tool: StringName) -> void:
	if _map_drag: map_drag_released.emit()
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
	_hint.text = "ui.construction.inspect_hint" if _map_drag else ("ui.construction.build_hint" if _tool == &"build" else "ui.construction.demolish_hint")
	if context.controller.terrain != null:
		var soil: TerrainType = context.controller.terrain.map.ground_at(_pricing_cell)
		if soil != null: _hint.text = tr(soil.display_name)
	var budget: PlacementCheck = draft.budget_check()
	_cost.text = tr("ui.construction.cost") % [draft.size(), BuildCostText.format(draft.costs())]
	_cost.add_theme_color_override("font_color", ColonyStyle.color(&"text") if budget.allowed() else ColonyStyle.color(&"danger"))
	controls[&"undo"].disabled = not draft.can_undo()
	controls[&"apply"].disabled = not budget.allowed()
	var reason: PlacementCheck = budget if not budget.allowed() else draft.last_result
	_status.text = PlacementMessages.text(reason.code)
	_status.visible = not reason.allowed()
	_status.add_theme_color_override("font_color", ColonyStyle.color(&"danger") if not reason.allowed() else ColonyStyle.color(&"muted"))
	_update_details()
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

func apply_plan() -> void:
	_end_stroke()
	var residents: int = draft.residents_to_demolish()
	if residents > 0:
		%PaletteHeader.set_collapsed(false)
		_confirm_label.text = tr("ui.build.confirm_residents") % residents
		_confirmation.show()
		return
	_commit()

func _commit() -> void:
	if draft.commit():
		if order_mode:
			order_mode = false
		close_requested.emit(self)
	else:
		%PaletteHeader.set_collapsed(false)
		_refresh()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or context == null: return
	if event is InputEventMouseMotion or event is InputEventMouseButton: _pointer = event.position
	if event is InputEventKey and event.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Z and event.ctrl_pressed:
		_undo()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if not context.dismiss_map_popup.is_valid() or not context.dismiss_map_popup.call():
			_header.set_collapsed(true)
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
		if event.button_index == MOUSE_BUTTON_LEFT and _map_drag:
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
	if not get_viewport_rect().has_point(point) or (panel.is_visible_in_tree() and panel.get_global_rect().has_point(point)):
		return false
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
		_queue_refresh()
		_preview.queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or context == null: return
	if not _painting:
		var direction: Vector2 = WorldCamera.keyboard_direction()
		if not direction.is_zero_approx():
			context.camera.pan(-direction.normalized() * delta * 100.0)
	_update_hover(_pointer)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_stroke()
		_panning = false
