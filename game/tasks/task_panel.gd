class_name TaskPanel
extends Control
## Lists the current royal requests independently, with authored variant cards.
const REQUEST: PackedScene = preload("res://game/tasks/task_request.tscn")
const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")

signal order_requested(task_id: StringName, variant_id: StringName)
signal info_requested(option: BuildOption)
signal strip_closed

var director: TaskDirector
var _queued := false
var _selection: TaskBuildOrder
var _bottom_inset := 0.0
var _pan_mode := false
var _pending_prices: Dictionary[String, int] = {}
@onready var _requests: HBoxContainer = %Requests
@onready var _waiting: Label = %Waiting
@onready var _categories: PanelContainer = %Categories
@onready var _category: Button = %Category
@onready var _strip: PanelContainer = %TaskStrip
@onready var _scroll: ScrollContainer = %Scroll

func _ready() -> void:
	%CategoryHeader.collapsed_changed.connect(func(_collapsed: bool): _layout_windows())
	%StripHeader.collapsed_changed.connect(func(_collapsed: bool): _layout_windows())
	_category.pressed.connect(AppSettings.play_click)
	_category.toggled.connect(func(_pressed: bool): _update_strip_visibility())
	_categories.minimum_size_changed.connect(_layout_windows.call_deferred)
	_requests.minimum_size_changed.connect(_layout_windows.call_deferred)
	AppSettings.language_changed.connect(_queue_refresh)
	AppSettings.text_size_changed.connect(_queue_refresh)
	director.changed.connect(_queue_refresh)
	director.world.inventory.changed.connect(_refresh_prices)
	director.world.prices.changed.connect(_refresh_prices)
	director.world.match_controller.time_changed.connect(_on_time_changed)
	_refresh()

func dock_above(bottom_bar_height: float) -> void:
	_bottom_inset = bottom_bar_height
	_layout_windows()

func visible_bounds() -> Array[Rect2]:
	var bounds: Array[Rect2] = []
	for window in [_categories, _strip]:
		if window.is_visible_in_tree():
			bounds.append(window.get_global_rect())
	return bounds

func set_pan_mode(enabled: bool) -> void:
	_pan_mode = enabled
	_update_strip_visibility()

func _update_strip_visibility() -> void:
	var was_open := _strip.visible
	_strip.visible = _category.button_pressed and not _pan_mode
	if was_open and not _strip.visible:
		strip_closed.emit()
	_layout_windows()

func _layout_windows() -> void:
	var viewport := get_viewport_rect().size
	var margin := PRESENTATION.dock_clearance
	var bottom := viewport.y - _bottom_inset - margin
	_categories.reset_size()
	%CategoryHeader.place(Vector2(margin, bottom - _categories.size.y))
	var left := _categories.position.x + _categories.size.x + margin
	var available_width := maxf(0.0, viewport.x - left - margin)
	var height_limit := floorf(viewport.y * PRESENTATION.task_strip_height_ratio)
	var header_height: float = %StripHeader.get_combined_minimum_size().y
	header_height += %StripHeader.get_parent().get_theme_constant(&"separation")
	height_limit += header_height
	var content := _requests.get_combined_minimum_size() + _strip.get_theme_stylebox(&"panel").get_minimum_size()
	content.y += header_height
	if %StripHeader.collapsed:
		content.y = header_height + _strip.get_theme_stylebox(&"panel").get_minimum_size().y
	if content.x > available_width:
		content.y += _scroll.get_h_scroll_bar().get_combined_minimum_size().y
	if content.y > height_limit:
		content.x += _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	_strip.size = Vector2(minf(content.x, available_width), minf(content.y, height_limit))
	%StripHeader.place(Vector2(left, bottom - _strip.size.y))

func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	_refresh.call_deferred()

func set_selection(order: TaskBuildOrder) -> void:
	_selection = order
	for request: TaskRequest in _requests.get_children():
		request.set_selection(order)

func _refresh() -> void:
	_queued = false
	var scroll_position := _scroll.scroll_horizontal
	for child in _requests.get_children():
		_requests.remove_child(child)
		child.queue_free()
	%Heading.text = tr("ui.task.level_progress") % [director.level, director.closed, director.stage().tasks.size()]
	for index in director.slots.size():
		var task := director.slots[index]
		if task == null:
			continue
		var request: TaskRequest = REQUEST.instantiate()
		_requests.add_child(request)
		request.configure(director, task, index + 1)
		request.refresh_prices(_pending_prices)
		request.set_selection(_selection)
		request.order_requested.connect(order_requested.emit)
		request.info_requested.connect(info_requested.emit)
	_scroll.set_deferred("scroll_horizontal", scroll_position)
	%Message.text = director.display_message()
	%Message.visible = not %Message.text.is_empty()
	_update_waiting()
	_layout_windows()

func _refresh_prices() -> void:
	for request: TaskRequest in _requests.get_children():
		request.refresh_prices(_pending_prices)
	_update_waiting()

func set_pending_prices(pending: Dictionary[String, int]) -> void:
	_pending_prices = pending
	_refresh_prices()

func _on_time_changed(_seconds: int) -> void:
	for request: TaskRequest in _requests.get_children():
		request.refresh_availability(director)
	_update_waiting()

func _update_waiting() -> void:
	var missing := 0
	var occupied := 0
	for ant in director.world.population.agents():
		if ant.status != AntAgent.Status.HOME: continue
		if ant.waiting_reason == WorkPlan.WaitReason.MISSING_INPUTS: missing += 1
		elif ant.waiting_reason == WorkPlan.WaitReason.SLOTS_FULL: occupied += 1
	if is_instance_valid(_waiting):
		_waiting.text = tr("ui.task.waiting") % [occupied, missing]
		_waiting.visible = occupied > 0 or missing > 0
