extends MenuBase
## Presentation only: the world controller owns validation and construction.

var _controller: BuildController
var _cell: Vector2i
var _buttons: Array[Button] = []
var _refresh_timer := 0.0


@onready var _title: Label = $CenterContainer/PanelContainer/VBoxContainer/TitleLabel
@onready var _inventory_label: Label = $CenterContainer/PanelContainer/VBoxContainer/InventoryLabel
@onready var _option_list: VBoxContainer = $CenterContainer/PanelContainer/VBoxContainer/ScrollContainer/VBoxContainer
@onready var _message: Label = $CenterContainer/PanelContainer/VBoxContainer/MessageLabel
@onready var _close: Button = $CenterContainer/PanelContainer/VBoxContainer/Button

func _ready() -> void:
	_controller = payload.controller
	_cell = payload.cell
	_title.text = "Build at (%d, %d)" % [_cell.x, _cell.y]
	for option in _controller.options:
		if option == null:
			continue
		var button := Button.new()
		button.icon = option.icon
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 12)
		button.set_meta("option", option)
		button.pressed.connect(_choose.bind(option))
		_option_list.add_child(button)
		_buttons.append(button)
	_close.pressed.connect(func(): close_requested.emit(self))
	if default_focus == null:
		default_focus = _close
	_controller.inventory.changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	# Occupancy can change while this non-pausing menu is open.
	_refresh_timer += delta
	if _refresh_timer >= 0.25:
		_refresh_timer = 0.0
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(_controller):
		close_requested.emit(self)
		return
	var stock: PackedStringArray = []
	for type in _controller.inventory.registered_types():
		stock.append("%s: %d" % [type.display_name, _controller.inventory.quantity(type)])
	_inventory_label.text = " | ".join(stock)
	for button in _buttons:
		var option := button.get_meta("option") as BuildOption
		var price := "Invalid cost"
		if option.cost != null and option.cost.type != null:
			price = "%d %s" % [option.cost.amount, option.cost.type.display_name]
		button.text = "%s — %s" % [option.display_name, price]
		button.tooltip_text = _controller.unavailable_reason(option, _cell)
		button.disabled = not button.tooltip_text.is_empty()


func _choose(option: BuildOption) -> void:
	if _controller.try_build(option, _cell):
		close_requested.emit(self)
	else:
		_message.text = "Cannot build here. Choose another option."
		_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			close_requested.emit(self)
