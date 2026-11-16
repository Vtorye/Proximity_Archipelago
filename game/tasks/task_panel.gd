class_name TaskPanel
extends PanelContainer
## Lists the current royal requests independently, with authored variant cards.
const REQUEST: PackedScene = preload("res://game/tasks/task_request.tscn")
const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")

signal order_requested(task_id: StringName, variant_id: StringName)
signal info_requested(option: BuildOption)

var director: TaskDirector
var _queued := false
@onready var _requests: VBoxContainer = %Requests
@onready var _waiting: Label = %Waiting
@onready var _header: WindowHeader = %WindowHeader
@onready var _scroll: ScrollContainer = %Scroll

func _ready() -> void:
	AppSettings.language_changed.connect(_queue_refresh)
	AppSettings.text_size_changed.connect(_queue_refresh)
	director.changed.connect(_queue_refresh)
	director.world.inventory.changed.connect(_refresh_prices)
	director.world.prices.changed.connect(_refresh_prices)
	director.world.match_controller.time_changed.connect(_on_time_changed)
	_refresh()

func dock_below(top_edge: float, bottom_bar_height: float) -> void:
	_header.inset.y = top_edge + PRESENTATION.dock_clearance
	if not _header.collapsed:
		var header_height: float = get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
		var lower_edge: float = get_viewport_rect().size.y - bottom_bar_height - PRESENTATION.dock_clearance
		_scroll.custom_minimum_size.y = maxf(0.0, lower_edge - _header.inset.y - header_height)
	_header.queue_layout()

func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	_refresh.call_deferred()

func _refresh() -> void:
	_queued = false
	var scroll_position: int = _scroll.scroll_vertical
	for child in _requests.get_children():
		_requests.remove_child(child)
		child.queue_free()
	%Heading.text = tr("ui.task.level_progress") % [director.level, director.closed, director.stage().tasks.size()]
	for task in director.slots:
		if task == null:
			continue
		var request: TaskRequest = REQUEST.instantiate()
		_requests.add_child(request)
		request.configure(director, task)
		request.order_requested.connect(order_requested.emit)
		request.info_requested.connect(info_requested.emit)
	_scroll.set_deferred("scroll_vertical", scroll_position)
	%Message.text = director.display_message()
	_update_waiting()

func _refresh_prices() -> void:
	for request: TaskRequest in _requests.get_children():
		request.refresh_prices()
	_update_waiting()

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
