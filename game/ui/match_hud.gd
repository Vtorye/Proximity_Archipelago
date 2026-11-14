class_name MatchHud
extends Control
signal settings_requested
signal navigation_requested
signal construction_requested
signal zoom_in_requested
signal zoom_out_requested
var world: World
var controls: Dictionary[StringName, Button] = {}
var stock_labels: Dictionary[StringName, Label] = {}
var stock_chips: Dictionary[StringName, Control] = {}
var progress: Dictionary[StringName, ProgressBar] = {}
@onready var _timer: Label = %Timer
@onready var _ants: Label = %Ants
@onready var _zoom: Label = %Zoom
@onready var _toast: Label = %Toast
var _toast_time := 0.0
@onready var _warning: Label = %Warning
@onready var _waiting: Label = %Waiting
var _zoom_level := 2
@onready var _objectives: PanelContainer = %Objectives
var navigation: NavigationOverlay
var navigation_panel: NavigationPanel
var task_panel: TaskPanel
var wave_hud: WaveHud
@onready var _bottom: PanelContainer = %Bottom

func configure(session: World, routes: NavigationOverlay) -> void:
	world = session
	navigation = routes
	if is_node_ready():
		_build_hud()

func _ready() -> void:
	if world != null:
		_build_hud()

func _build_hud() -> void:
	ColonyStyle.apply(self)
	var row: HBoxContainer = %Counters
	for type in world.inventory.registered_types():
		var chip: HBoxContainer = preload("res://game/ui/hud_resource_chip.tscn").instantiate()
		var icon: TextureRect = chip.get_node("Icon")
		icon.texture = _resource_icon(type.id)
		stock_chips[type.id] = chip
		stock_labels[type.id] = chip.get_node("Amount")
		row.add_child(chip)
		row.move_child(chip, stock_chips.size() - 1)
	var goals: VBoxContainer = %Goals
	%GoalTitle.text = tr("ui.hud.goal") % world.match_controller.target_amount
	for type in world.match_controller.tracked_types:
		var line: HBoxContainer = preload("res://game/ui/hud_resource_goal.tscn").instantiate()
		var caption: Label = line.get_node("Caption")
		caption.text = type.display_name
		var bar: ProgressBar = line.get_node("Progress")
		bar.max_value = world.match_controller.target_amount
		bar.add_theme_stylebox_override("background", ColonyStyle.box(Color("151515"), Color("555555"), 0))
		bar.add_theme_stylebox_override("fill", ColonyStyle.box(ColonyStyle.ACCENT, ColonyStyle.ACCENT, 0))
		progress[type.id] = bar
		goals.add_child(line)
		goals.move_child(line, progress.size())
	var compact_panel: StyleBoxTexture = ColonyStyle.box()
	compact_panel.content_margin_top = 2
	compact_panel.content_margin_bottom = 2
	_bottom.add_theme_stylebox_override("panel", compact_panel)
	_toast.add_theme_stylebox_override("normal", ColonyStyle.box())
	controls[&"routes"] = %Routes
	%Routes.pressed.connect(AppSettings.play_click)
	%Routes.pressed.connect(func(): navigation_requested.emit())
	controls[&"settings"] = %Settings
	%Settings.pressed.connect(AppSettings.play_click)
	%Settings.pressed.connect(func(): settings_requested.emit())
	controls[&"build"] = %Build
	%Build.pressed.connect(AppSettings.play_click)
	%Build.pressed.connect(func(): construction_requested.emit())
	controls[&"zoom_out"] = %ZoomOut
	%ZoomOut.pressed.connect(AppSettings.play_click)
	%ZoomOut.pressed.connect(func(): zoom_out_requested.emit())
	controls[&"zoom_in"] = %ZoomIn
	%ZoomIn.pressed.connect(AppSettings.play_click)
	%ZoomIn.pressed.connect(func(): zoom_in_requested.emit())
	world.inventory.changed.connect(refresh)
	world.population.changed.connect(refresh)
	world.match_controller.time_changed.connect(_on_time_changed)
	if world.tasks != null:
		_objectives.hide()
		task_panel = preload("res://game/tasks/task_panel.tscn").instantiate()
		task_panel.director = world.tasks
		add_child(task_panel)
	if navigation != null:
		navigation_panel = preload("res://game/ui/navigation_panel.tscn").instantiate()
		navigation_panel.process_mode = Node.PROCESS_MODE_ALWAYS
		navigation_panel.overlay = navigation
		add_child(navigation_panel)
	if world.combat != null:
		wave_hud = preload("res://game/combat/wave_hud.tscn").instantiate()
		wave_hud.director = world.combat
		add_child(wave_hud)
	refresh()
	set_zoom(2)
	set_navigation_mode(0)

func _resource_icon(id: StringName) -> Texture2D:
	var type: ResourceType = world.inventory.type_by_id(id)
	if type != null and type.icon != null: return type.icon
	return world.art.berries if id == &"food" else (world.art.timber if id == &"wood" else world.art.stone)

func refresh() -> void:
	for type in world.inventory.registered_types():
		stock_labels[type.id].text = "%d(%d)" % [world.inventory.quantity(type), world.inventory.available(type)] if type.id == &"food" else str(world.inventory.quantity(type))
		var total: String = tr("ui.hud.stock") % [tr(type.display_name), world.inventory.quantity(type), world.inventory.available(type)]
		stock_chips[type.id].tooltip_text = total + "\n" + (tr("ui.storage.in_main") % world.inventory.main_quantity(type))
		if progress.has(type.id):
			progress[type.id].value = world.inventory.quantity(type)
	var agents: Array[AntAgent] = world.population.agents()
	_ants.text = str(agents.size())
	var busy := 0
	var unsafe_work := 0
	var missing_inputs := 0
	var storage_full := 0
	for ant in agents:
		if ant.status != AntAgent.Status.HOME: continue
		if ant.waiting_reason == WorkPlan.WaitReason.SLOTS_FULL: busy += 1
		elif ant.waiting_reason == WorkPlan.WaitReason.NO_SAFE_WORK: unsafe_work += 1
		elif ant.waiting_reason == WorkPlan.WaitReason.MISSING_INPUTS: missing_inputs += 1
		elif ant.waiting_reason == WorkPlan.WaitReason.STORAGE_FULL: storage_full += 1
	_waiting.text = tr("ui.hud.waiting") % busy if busy > 0 else ""
	if unsafe_work > 0:
		_waiting.text += ("\n" if busy > 0 else "") + tr("ui.hud.no_safe_work") % unsafe_work
	if missing_inputs > 0:
		_waiting.text += ("\n" if not _waiting.text.is_empty() else "") + tr("ui.hud.missing_inputs") % missing_inputs
	if storage_full > 0:
		_waiting.text += ("\n" if not _waiting.text.is_empty() else "") + tr("ui.hud.storage_full") % storage_full
	_waiting.visible = busy > 0 or unsafe_work > 0 or missing_inputs > 0 or storage_full > 0
	var food: ResourceType = world.inventory.type_by_id(&"food")
	_warning.text = "ui.hud.need_food" if world.inventory.available(food) < 3 else ""

func _on_time_changed(seconds: int) -> void:
	_timer.text = "%d:%02d" % [seconds / 60, seconds % 60]
	_timer.add_theme_color_override("font_color", ColonyStyle.DANGER if seconds <= 30 else ColonyStyle.ACCENT)

func set_zoom(value: int) -> void:
	_zoom_level = value
	_zoom.text = "%sx" % str(WorldCamera.ZOOMS[value])
	controls[&"zoom_in"].disabled = value >= WorldCamera.MAX_LEVEL
	controls[&"zoom_out"].disabled = value <= WorldCamera.MIN_LEVEL

func build_obstacles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	result.append(%Top.get_global_rect())
	var goals_panel: Control = task_panel if task_panel != null else _objectives
	if goals_panel.is_visible_in_tree():
		result.append(goals_panel.get_global_rect())
	if wave_hud != null and wave_hud.is_visible_in_tree():
		result.append(wave_hud.get_global_rect())
	if navigation_panel != null and navigation_panel.is_visible_in_tree() and navigation_panel.mouse_filter == Control.MOUSE_FILTER_STOP:
		result.append(navigation_panel.get_global_rect())
	return result

func lock_zoom(locked: bool) -> void:
	_toast.visible = _toast_time > 0.0 and not locked
	controls[&"zoom_in"].disabled = locked or _zoom_level >= WorldCamera.MAX_LEVEL
	controls[&"zoom_out"].disabled = locked or _zoom_level <= WorldCamera.MIN_LEVEL

func toast(message: String, danger: bool = false) -> void:
	_toast.text = message
	_toast.add_theme_color_override("font_color", ColonyStyle.DANGER if danger else ColonyStyle.TEXT)
	_toast_time = 3.0
	_toast.show()

func set_construction_mode(active: bool) -> void:
	_bottom.visible = not active
	if task_panel != null:
		task_panel.visible = not active
	else:
		_objectives.visible = not active
	_toast.hide()

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.hide()

func set_navigation_mode(mode: int) -> void:
	var routes: Button = controls[&"routes"]
	routes.set_pressed_no_signal(mode > 0)
	routes.text = ["ui.hud.routes", "ui.hud.routes_cells", "ui.hud.routes_priority"][mode]
	if navigation_panel != null:
		navigation_panel.refresh()
	var texture: Texture2D = preload("res://game/assets/ui/opaque_panel.svg") if mode > 0 else preload("res://game/assets/ui/panel.svg")
	# Keep world labels behind readable HUD surfaces without clipping the map layer.
	for style in [theme.get_stylebox("panel", "PanelContainer"), theme.get_stylebox("panel", "TooltipPanel"), _bottom.get_theme_stylebox("panel"), _toast.get_theme_stylebox("normal")]:
		(style as StyleBoxTexture).texture = texture
