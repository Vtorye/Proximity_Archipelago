class_name WindowHeader
extends HBoxContainer
## Moves a panel within its viewport and folds its body without destroying its contents.
signal collapsed_changed(collapsed: bool)
signal close_requested

enum Action { NONE, FOLD, CLOSE }

enum Dock { CENTER, BOTTOM_LEFT, BOTTOM_RIGHT, TOP_LEFT, TOP_RIGHT, TOP_CENTER }

@export var title: String
@export var action: Action = Action.NONE
@export var draggable := true
@export_range(0.0, 624.0, 1.0) var collapsed_width := 0.0
@export var dock: Dock = Dock.CENTER
## Preferred width in logical pixels independent of text size.
@export_range(64.0, 624.0, 1.0) var panel_width := 260.0
@export var inset := Vector2(8, 8)
@export var panel: PanelContainer
@export var body: Control

var collapsed := false
var _dragging := false
var _floating := false
var _layout_pending := false

@onready var handle: Label = %Handle
@onready var toggle: Button = %Toggle

func _ready() -> void:
	handle.text = title
	if draggable:
		handle.gui_input.connect(_drag_input)
	else:
		handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		handle.mouse_default_cursor_shape = Control.CURSOR_ARROW
	toggle.pressed.connect(AppSettings.play_click)
	toggle.visible = action != Action.NONE
	if action == Action.CLOSE:
		toggle.icon = preload("res://game/assets/ui/build_cancel.svg")
		toggle.text = ""
		toggle.tooltip_text = "ui.window.close"
		toggle.pressed.connect(close_requested.emit)
	elif action == Action.FOLD:
		toggle.pressed.connect(func(): set_collapsed(not collapsed))
	visibility_changed.connect(func():
		_dragging = false
		if is_visible_in_tree():
			queue_layout())
	if panel == null or body == null:
		return
	get_viewport().size_changed.connect(queue_layout)
	panel.minimum_size_changed.connect(queue_layout)
	queue_layout()

func set_title(value: String) -> void:
	title = value
	if is_node_ready():
		handle.text = value

func set_collapsed(value: bool) -> void:
	if action != Action.FOLD or collapsed == value or body == null:
		return
	collapsed = value
	body.visible = not collapsed
	toggle.text = "+" if collapsed else "−"
	toggle.tooltip_text = "ui.window.expand" if collapsed else "ui.window.collapse"
	queue_layout()
	collapsed_changed.emit(collapsed)

func queue_layout() -> void:
	if not _layout_pending:
		_layout_pending = true
		_layout.call_deferred()

func _layout() -> void:
	_layout_pending = false
	if not is_instance_valid(panel) or not panel.is_visible_in_tree():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var area: Vector2 = inset
	var minimum: Vector2 = panel.get_combined_minimum_size()
	var preferred: float = collapsed_width if collapsed and collapsed_width > 0.0 else panel_width
	var width: float = minf(preferred, viewport_size.x - 2.0 * area.x)
	panel.size = Vector2(maxf(minimum.x, width), minimum.y).ceil()
	if not _floating:
		var mid: Vector2 = (viewport_size - panel.size) * 0.5
		var far: Vector2 = viewport_size - panel.size - area
		match dock:
			Dock.CENTER: panel.position = mid
			Dock.BOTTOM_LEFT: panel.position = Vector2(area.x, far.y)
			Dock.BOTTOM_RIGHT: panel.position = far
			Dock.TOP_LEFT: panel.position = Vector2(area.x, inset.y)
			Dock.TOP_RIGHT: panel.position = Vector2(far.x, inset.y)
			Dock.TOP_CENTER: panel.position = Vector2(mid.x, inset.y)
	_clamp_panel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false

func _clamp_panel() -> void:
	panel.position = panel.position.clamp(Vector2.ZERO, (get_viewport_rect().size - panel.size).max(Vector2.ZERO)).round()

func _drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		handle.accept_event()

func _input(event: InputEvent) -> void:
	if not draggable or not _dragging or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_dragging = false
			return
		_floating = true
		panel.position += event.relative
		_clamp_panel()
		get_viewport().set_input_as_handled()
