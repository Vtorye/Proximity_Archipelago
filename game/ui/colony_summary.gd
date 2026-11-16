class_name ColonySummary
extends PanelContainer

signal nest_selected(nest: House)
signal expanded_changed(expanded: bool)

var _world: World
var _rows: Dictionary[House, PanelContainer] = {}
var _rebuild_pending := false
@onready var _summary: Button = %Summary
@onready var _scroll: ScrollContainer = %Stores

func is_expanded() -> bool:
	return _summary.button_pressed

func set_expanded(expanded: bool) -> void:
	_summary.set_pressed_no_signal(expanded)
	_scroll.visible = expanded
	refresh()

func configure(session: World) -> void:
	_world = session
	%PreviewStore.hide()
	_scroll.hide()
	_summary.toggled.connect(func(expanded: bool):
		_scroll.visible = expanded
		refresh()
		expanded_changed.emit(expanded))
	_summary.pressed.connect(AppSettings.play_click)
	session.inventory.changed.connect(refresh)
	session.population.changed.connect(refresh)
	session.registry.added.connect(_on_nest_changed)
	session.registry.removed.connect(_on_nest_changed)
	AppSettings.language_changed.connect(refresh)
	_rebuild_rows()

func _on_nest_changed(building: Building) -> void:
	if building is House and not _rebuild_pending:
		_rebuild_pending = true
		_rebuild_rows.call_deferred()

func _rebuild_rows() -> void:
	_rebuild_pending = false
	if not is_inside_tree() or not is_instance_valid(_world):
		return
	for row in _rows.values():
		row.get_parent().remove_child(row)
		row.queue_free()
	_rows.clear()
	var nests: Array[House] = _world.logistics.nests()
	var primary: House = _world.logistics.main_nest
	for group in range(3):
		for nest in nests:
			var rank: int = 0 if nest == primary else (1 if nest.is_main_nest else 2)
			if rank != group:
				continue
			var row: PanelContainer = preload("res://game/ui/colony_store_row.tscn").instantiate()
			%Rows.add_child(row)
			var focus: Button = row.get_node("Content/Focus")
			focus.pressed.connect(AppSettings.play_click)
			focus.pressed.connect(nest_selected.emit.bind(nest))
			row.gui_input.connect(_on_row_input.bind(nest))
			_rows[nest] = row
	refresh()

func refresh() -> void:
	var types: Array[ResourceType] = _world.inventory.registered_types().filter(
		func(type: ResourceType) -> bool: return type.id != WorldInventory.CURRENCY_ID)
	var nests: Array[House] = _world.logistics.nests()
	var totals: RichTextLabel = %Totals
	totals.clear()
	for type in types:
		var total := 0
		for nest in nests:
			total += _world.inventory.stock_of(_world.logistics.store_of(nest), type)
		_append_stock(totals, type, total)
	var marker: String = "−" if _summary.button_pressed else "+"
	_summary.text = "%s  %s" % [marker, tr("ui.colony.population") % _world.population.count()]
	for nest in _rows:
		if not is_instance_valid(nest) or not _world.logistics.owns(nest):
			_rows[nest].hide()
			continue
		var amounts: RichTextLabel = _rows[nest].get_node("Content/Amounts")
		amounts.clear()
		for type in types:
			_append_stock(amounts, type, _world.inventory.stock_of(_world.logistics.store_of(nest), type))
		var title: String = tr(nest.display_title())
		_rows[nest].get_node("Content/Focus").text = tr("ui.colony.store") % [title, nest.cell.x, nest.cell.y]

func _on_row_input(event: InputEvent, nest: House) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AppSettings.play_click()
		nest_selected.emit(nest)
		get_viewport().set_input_as_handled()

func _append_stock(label: RichTextLabel, type: ResourceType, amount: int) -> void:
	if not label.get_parsed_text().is_empty():
		label.add_text(BuildCostText.RESOURCE_GAP)
	BuildCostText.append_resource(label, type, str(amount))
