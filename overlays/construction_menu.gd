class_name ConstructionMenu
extends MenuBase

const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")
const CARD: PackedScene = preload("res://game/ui/construction_card.tscn")

## Construction editor. The draft owns edits; the controller commits the final plan.
signal map_inspection_requested(cell: Vector2i)
var order_option: BuildOption

var context: ConstructionContext
var draft := BuildDraft.new()
var controls: Dictionary[StringName, Button] = {}
@onready var panel: PanelContainer = %Panel
@onready var buildings_panel: PanelContainer = %BuildingsPanel
@onready var description_panel: PanelContainer = %DescriptionPanel
@onready var _building_scroll: ScrollContainer = %Buildings
@onready var _choices: HBoxContainer = %Choices
@onready var _category_scroll: ScrollContainer = %CategoryScroll
@onready var _category_list: VBoxContainer = %CategoryList
@onready var _cost: RichTextLabel = %Cost
@onready var _status: Label = %Status
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
var _active_category: Button
var _described_option: BuildOption

var _pricing_cell := Vector2i(2147483647, 2147483647)
var _bottom_inset := 8.0
var _top_edge := 0.0

func is_palette_open() -> bool:
	return panel.visible

func set_palette_visible(shown: bool) -> void:
	_end_stroke()
	panel.visible = shown
	if not shown:
		buildings_panel.hide()
		description_panel.hide()
	if shown:
		_update_buildings_visibility()
		_layout_windows()

func _update_buildings_visibility() -> void:
	buildings_panel.visible = panel.visible and not _map_drag and (_active_category != null or order_option != null)

func detach_undo() -> void:
	controls[&"undo"].pressed.disconnect(_undo)
	controls[&"undo"].pressed.disconnect(AppSettings.play_click)
	controls[&"undo"].disabled = true

func dock_between(bar_height: float, top_edge: float) -> void:
	_bottom_inset = bar_height + PRESENTATION.dock_clearance
	_top_edge = top_edge + PRESENTATION.dock_clearance
	_layout_windows()

func _layout_windows() -> void:
	if not is_node_ready(): return
	var viewport: Vector2 = get_viewport_rect().size
	var margin: float = PRESENTATION.dock_clearance
	var bottom: float = viewport.y - _bottom_inset
	var fixed_height: float = panel.get_combined_minimum_size().y - _category_scroll.get_combined_minimum_size().y
	var available_height: float = maxf(0.0, bottom - _top_edge - fixed_height)
	_category_scroll.custom_minimum_size.y = minf(available_height, _category_list.get_combined_minimum_size().y)
	panel.reset_size()
	var frame: Vector2 = buildings_panel.get_theme_stylebox(&"panel").get_minimum_size()
	var content: Vector2 = _choices.get_combined_minimum_size() + frame
	var left := margin
	if order_option != null:
		left = maxf(margin, viewport.x - panel.size.x - content.x - 2.0 * margin)
	panel.position = Vector2(left, bottom - panel.size.y)
	var strip_left: float = panel.position.x + panel.size.x + margin
	var available_width: float = maxf(0.0, viewport.x - strip_left - margin)
	if content.x > available_width:
		content.y += _building_scroll.get_h_scroll_bar().get_combined_minimum_size().y
	buildings_panel.size = Vector2(minf(content.x, available_width), minf(content.y, viewport.y / 6.0))
	buildings_panel.position = Vector2(strip_left, bottom - buildings_panel.size.y)
	description_panel.size = Vector2(minf(400.0, viewport.x - 2.0 * margin), 0.0)
	description_panel.position = Vector2(viewport.x - description_panel.size.x - margin,
		maxf(margin, buildings_panel.position.y - description_panel.size.y - margin))

func _ready() -> void:
	%PreviewCategory.hide()
	%PreviewCard.hide()
	%CloseDescription.pressed.connect(AppSettings.play_click)
	%CloseDescription.pressed.connect(func(): description_panel.hide())
	_pointer = get_viewport().get_mouse_position()
	dismissable = false
	visibility_changed.connect(_on_visibility_changed)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	controls[&"undo"] = context.undo_button
	controls[&"demolish"] = %Demolish
	controls[&"apply"] = %Apply
	controls[&"cancel"] = %Cancel
	controls[&"move"] = %Move
	for action in [&"undo", &"apply", &"cancel", &"demolish", &"move"]:
		controls[action].pressed.connect(AppSettings.play_click)
	controls[&"undo"].pressed.connect(_undo)
	controls[&"demolish"].pressed.connect(select_demolition)
	controls[&"cancel"].pressed.connect(_cancel)
	controls[&"apply"].pressed.connect(apply_plan)
	%Move.toggled.connect(_set_map_drag)
	controls[&"confirm_demolish"] = %Confirm
	%Confirm.pressed.connect(AppSettings.play_click)
	%Confirm.pressed.connect(_commit)
	controls[&"keep_residents"] = %KeepResidents
	%KeepResidents.pressed.connect(AppSettings.play_click)
	%KeepResidents.pressed.connect(_cancel_confirmation)
	if order_option != null:
		%Demolish.disabled = true
		_add_card(order_option)
		buildings_panel.show()

		_select(order_option)
	else:
		_populate_categories()
		buildings_panel.hide()
	_layout_windows()
	get_viewport().size_changed.connect(_layout_windows)
	panel.minimum_size_changed.connect(_layout_windows.call_deferred)
	_category_list.minimum_size_changed.connect(_layout_windows.call_deferred)
	_choices.minimum_size_changed.connect(_layout_windows.call_deferred)
	description_panel.minimum_size_changed.connect(_layout_windows.call_deferred)
	draft.changed.connect(_cancel_confirmation)
	if context.controller.prices != null: context.controller.prices.changed.connect(func():
		draft.last_result = PlacementCheck.new()
		_queue_refresh())
	context.controller.inventory.changed.connect(_queue_refresh)
	context.controller.registry.removed.connect(draft.forget_removal)
	context.controller.registry.changed.connect(_queue_refresh)
	AppSettings.language_changed.connect(_queue_refresh)
	draft.changed.connect(_queue_refresh)
	_refresh()
	default_focus = controls.get(_selected.id) if _selected != null else null

func _populate_categories() -> void:
	var remaining: Array[BuildOption] = context.controller.options.duplicate()
	var catalog: BuildCatalog = context.controller.catalog
	var production: Button
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
			var entry: Button = _add_category(category.title, available)
			if category.title == "ui.construction.category.production":
				production = entry
	remaining = remaining.filter(func(option: BuildOption) -> bool: return option != null)
	_add_category("ui.construction.category.other", remaining)
	# Move starts before the generated categories, so the old index puts it directly after Production.
	%CategoryList.move_child(%Move, production.get_index() if production != null else -1)

func _add_category(title: String, options: Array[BuildOption]) -> Button:
	if options.is_empty():
		return null
	var category: Button = preload("res://game/ui/palette_entry.tscn").instantiate()
	category.text = tr(title)
	category.tooltip_text = tr(title)
	category.toggle_mode = true
	category.pressed.connect(AppSettings.play_click)
	category.pressed.connect(_show_category.bind(category))
	%CategoryList.add_child(category)
	category_buttons.append(category)
	for option in options:
		_add_card(option).hide()
		_category_for[option.id] = category
	return category

func _add_card(option: BuildOption) -> ConstructionCard:
	var entry: ConstructionCard = CARD.instantiate()
	entry.button_group = %PreviewCard.button_group
	entry.pressed.connect(AppSettings.play_click)
	entry.pressed.connect(_select.bind(option))
	entry.info_requested.connect(_toggle_description)
	_choices.add_child(entry)
	entry.configure(option, context.art)
	controls[option.id] = entry
	return entry

func show_category_for(option_id: StringName) -> void:
	var category: Button = _category_for.get(option_id)
	if category != null:
		_show_category(category)

func _show_category(category: Button) -> void:
	_active_category = category
	_building_scroll.scroll_horizontal = 0
	if _map_drag:
		_set_map_drag(false)
	_update_buildings_visibility()
	description_panel.hide()
	for button in category_buttons:
		button.set_pressed_no_signal(button == category)
	for id in _category_for:
		controls[id].visible = _category_for[id] == category
	_layout_windows.call_deferred()

func _toggle_description(option: BuildOption) -> void:
	if description_panel.visible and _described_option == option:
		description_panel.hide()
		return
	_described_option = option
	_refresh_description(option)
	description_panel.show()
	_layout_windows.call_deferred()

func _refresh_description(option: BuildOption) -> void:
	%BuildingName.text = tr(option.display_name)
	%Description.text = tr(option.description)
	var price: Array[ResourceAmount] = context.controller.price(option, _pricing_cell)
	var details := PackedStringArray()
	var size := _footprint_size(option)
	details.append(tr("ui.construction.size") % [size.x, size.y])
	if option is NestBuildOption:
		details.append(tr("ui.construction.residents") % option.resident_capacity)
		details.append(tr("ui.construction.storage") % option.stock_capacity())
	if context.controller.construction != null and ConstructionService.needs_builders(option, price):
		details.append(tr("ui.construction.time") % str(option.construction_seconds))
	else:
		details.append(tr("ui.construction.instant"))
	if option is SceneBuildOption:
		if option.requires_water: details.append(tr("ui.construction.water"))
	elif option is WorkplaceUpgradeOption:
		details.append(tr("ui.construction.slots") % option.added_slots)
	elif option is TileBuildOption:
		var terrain_map := context.controller.map as TerrainMap
		if terrain_map != null:
			var terrain: TerrainType = terrain_map.catalog.for_tile(Vector4i(option.source_id, option.atlas_coords.x, option.atlas_coords.y, option.alternative_tile))
			if terrain != null: details.append(tr("ui.construction.speed") % str(terrain.move_cost))
	_update_price_growth(option, details)
	%Parameters.text = "\n".join(details)
	BuildCostText.show_price(%Price, price, tr("ui.construction.price"))

func _footprint_size(option: BuildOption) -> Vector2i:
	var cells: Array[Vector2i] = context.controller.footprint_at(option, Vector2i.ZERO)
	if cells.is_empty():
		return Vector2i.ZERO
	var first: Vector2i = cells[0]
	var last: Vector2i = first
	for cell in cells:
		first = first.min(cell)
		last = last.max(cell)
	return last - first + Vector2i.ONE

func _update_price_growth(option: BuildOption, details: PackedStringArray) -> void:
	var event := GameEvents.Kind.TERRAIN_CHANGED if option is TileBuildOption else GameEvents.Kind.BUILDING_BUILT
	var next_price: RichTextLabel = %NextPrice
	if context.controller.prices != null:
		var changes_price := false
		for rule in option.price_rules:
			if rule == null or rule.event != event or (rule.subject != &"" and rule.subject != option.id):
				continue
			if (rule.operation == 0 and rule.value == 1.0) or (rule.operation == 1 and rule.value == 0.0):
				continue
			if rule.resource != null and not option.costs.any(func(cost: ResourceAmount) -> bool:
				return cost != null and cost.type != null and cost.type.id == rule.resource.id):
				continue
			changes_price = true
			var key := "ui.construction.price_multiplier" if rule.operation == 0 else "ui.construction.price_add"
			if rule.resource != null:
				key = "ui.construction.price_partial_multiplier" if rule.operation == 0 else "ui.construction.price_partial_add"
			details.append(tr(key) % String.num(rule.value).trim_suffix(".0"))
		if changes_price:
			var pending: Dictionary[String, int] = {
				PriceService.key(event, option.id): 1,
				PriceService.key(event, &""): 1,
			}
			BuildCostText.show_price(next_price, context.controller.price(option, _pricing_cell, pending),
				tr("ui.construction.next_price"))
			next_price.show()
			return
	next_price.hide()
	if option is SceneBuildOption:
		details.append(tr("ui.construction.price_constant"))

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
	if _map_drag: _set_map_drag(false)
	_end_stroke()
	_tool = &"build"
	_selected = option
	_preview.demolishing = false
	if controls.has(option.id): controls[option.id].set_pressed_no_signal(true)
	_preview.option = option
	_preview.queue_redraw()
	_refresh()

func _set_map_drag(enabled: bool) -> void:
	_end_stroke()
	_panning = false
	context.camera.dragging = false
	_map_drag = enabled
	%Move.set_pressed_no_signal(enabled)
	_update_buildings_visibility()
	if enabled:
		description_panel.hide()
	_preview.option = _selected if not enabled and _tool == &"build" else null
	_preview.demolishing = not enabled and _tool == &"demolish"
	_refresh()

func select_demolition() -> void:
	if _map_drag: _set_map_drag(false)
	if _tool == &"demolish":
		if _selected != null:
			_select(_selected)
		else:
			_tool = &"build"
			_preview.demolishing = false
			_refresh()
		return
	_end_stroke()
	_tool = &"demolish"
	var selected_card: Button = controls.get(_selected.id) if _selected != null else null
	if selected_card != null: selected_card.set_pressed_no_signal(false)
	_preview.option = null
	_preview.demolishing = true
	_preview.queue_redraw()
	_refresh()

func _cancel_confirmation() -> void:
	if _confirmation != null: _confirmation.hide()

func _refresh() -> void:
	_refresh_queued = false
	for control in controls.values():
		var card := control as ConstructionCard
		if card != null and card.option != null:
			card.set_price(context.controller.price(card.option, _pricing_cell))
	var budget: PlacementCheck = draft.budget_check()
	BuildCostText.show_price(_cost, draft.costs(), tr("ui.construction.cost") % [draft.size(), "%s"])
	_cost.add_theme_color_override("default_color", ColonyStyle.color(&"text") if budget.allowed() else ColonyStyle.color(&"danger"))
	controls[&"demolish"].set_pressed_no_signal(_tool == &"demolish")
	controls[&"undo"].disabled = not draft.can_undo()
	controls[&"apply"].disabled = draft.size() == 0 or not budget.allowed()
	var reason: PlacementCheck = budget if not budget.allowed() else draft.last_result
	_status.text = PlacementMessages.text(reason.code)
	_status.visible = not reason.allowed()
	_status.add_theme_color_override("font_color", ColonyStyle.color(&"danger") if not reason.allowed() else ColonyStyle.color(&"muted"))
	if description_panel.visible and _described_option != null:
		_refresh_description(_described_option)
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
	if draft.size() == 0: return
	_end_stroke()
	var residents: int = draft.residents_to_demolish()
	if residents > 0:
		set_palette_visible(true)
		_confirm_label.text = tr("ui.build.confirm_residents") % residents
		_confirmation.show()
		return
	_commit()

func _commit() -> void:
	if draft.commit():
		close_requested.emit(self)
	else:
		set_palette_visible(true)
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
			set_palette_visible(false)
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
	if not get_viewport_rect().has_point(point):
		return false
	for window: Control in [panel, buildings_panel, description_panel]:
		if window.is_visible_in_tree() and window.get_global_rect().has_point(point):
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
