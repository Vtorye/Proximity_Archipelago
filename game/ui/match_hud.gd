class_name MatchHud
extends Control

const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")
const ResourceChip = preload("res://game/ui/hud_resource_chip.gd")
signal nest_selected(nest: House)
signal settings_requested
signal pause_requested
signal navigation_requested
signal construction_requested
signal order_requested(task_id: StringName, variant_id: StringName)
signal section_requested(section: StringName)
signal construction_bounds_changed
signal zoom_in_requested
signal zoom_out_requested
var world: World
var controls: Dictionary[StringName, Button] = {}
var stock_chips: Dictionary[StringName, ResourceChip] = {}
var progress: Dictionary[StringName, ProgressBar] = {}
@onready var _timer: Label = %Timer
@onready var colony_summary: ColonySummary = %ColonySummary
@onready var _zoom: Label = %Zoom
@onready var _toast: Label = %Toast
var _toast_time := 0.0
@onready var _warning: Label = %Warning
@onready var _waiting: Label = %Waiting
var _zoom_level := 2
var _active_section: StringName
@onready var _objectives: PanelContainer = %Objectives
var navigation: NavigationOverlay
@onready var navigation_panel: NavigationPanel = %NavigationPanel
var task_panel: TaskPanel
@onready var _bottom: PanelContainer = %Bottom
@onready var _task_details: BuildDetailsPanel = %TaskDetails

func configure(session: World, routes: NavigationOverlay) -> void:
	world = session
	navigation = routes
	if is_node_ready():
		_build_hud()

func _ready() -> void:
	if world != null:
		_build_hud()

func _build_hud() -> void:
	colony_summary.configure(world)
	colony_summary.nest_selected.connect(nest_selected.emit)
	colony_summary.expanded_changed.connect(_on_colony_expanded)
	var regalia: ResourceType = world.inventory.type_by_id(WorldInventory.CURRENCY_ID)
	if regalia != null:
		var chip: ResourceChip = preload("res://game/ui/hud_resource_chip.tscn").instantiate()
		chip.configure(regalia)
		stock_chips[regalia.id] = chip
		%Counters.add_child(chip)
		%Counters.move_child(chip, 0)
	var goals: VBoxContainer = %Goals
	%GoalTitle.text = tr("ui.hud.goal") % world.match_controller.target_amount
	for type in world.match_controller.tracked_types:
		var line: HBoxContainer = preload("res://game/ui/hud_resource_goal.tscn").instantiate()
		var icon: TextureRect = line.get_node("Icon")
		icon.texture = type.icon
		line.tooltip_text = type.display_name
		var bar: ProgressBar = line.get_node("Progress")
		bar.max_value = world.match_controller.target_amount


		progress[type.id] = bar
		goals.add_child(line)
		goals.move_child(line, progress.size())
	_toast.add_theme_stylebox_override("normal", theme.get_stylebox("panel", "PanelContainer"))
	controls[&"routes"] = %Routes
	%Routes.pressed.connect(AppSettings.play_click)
	%Routes.pressed.connect(func(): navigation_requested.emit())
	controls[&"pause"] = %Pause
	%Pause.pressed.connect(AppSettings.play_click)
	%Pause.pressed.connect(func(): pause_requested.emit())
	PauseController.pause_changed.connect(_refresh_pause_indicator)
	_refresh_pause_indicator(get_tree().paused)
	controls[&"settings"] = %Settings
	%Settings.pressed.connect(AppSettings.play_click)
	%Settings.pressed.connect(func(): settings_requested.emit())
	controls[&"build"] = %Build
	%Build.pressed.connect(AppSettings.play_click)
	%Build.pressed.connect(func(): construction_requested.emit())
	%ColonyTab.pressed.connect(AppSettings.play_click)
	%ColonyTab.pressed.connect(func(): section_requested.emit(&"colony"))
	%TasksTab.pressed.connect(AppSettings.play_click)
	%TasksTab.pressed.connect(func(): section_requested.emit(&"tasks"))
	_bottom.resized.connect(construction_bounds_changed.emit)
	colony_summary.resized.connect(construction_bounds_changed.emit)
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
		task_panel.order_requested.connect(_request_task_order)
		task_panel.info_requested.connect(_show_task_details)
		task_panel.strip_closed.connect(_task_details.hide)
		construction_bounds_changed.connect(_layout_task_panel)
		get_viewport().size_changed.connect(_layout_task_panel)
		_layout_task_panel.call_deferred()
	if navigation != null:
		navigation_panel.configure(navigation)
	if world.combat != null:
		%WaveTimer.show()
		world.combat.changed.connect(_refresh_wave_timer)
		_refresh_wave_timer()
	AppSettings.language_changed.connect(_refresh_localized_labels)
	set_section(&"")
	refresh()
	_on_time_changed(ceili(world.match_controller.starting_duration()))
	set_zoom(2)
	set_navigation_mode(0)

func refresh() -> void:
	for type in world.inventory.registered_types():
		if stock_chips.has(type.id):
			stock_chips[type.id].set_amount(world.inventory.quantity(type))
		if progress.has(type.id):
			progress[type.id].value = world.inventory.quantity(type)
	var agents: Array[AntAgent] = world.population.agents()
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
	_warning.text = "ui.hud.need_food" if world.inventory.available(food) < PRESENTATION.low_food_threshold else ""

func _refresh_localized_labels() -> void:
	%GoalTitle.text = tr("ui.hud.goal") % world.match_controller.target_amount
	_on_time_changed(ceili(world.match_controller.time_remaining))
	if world.combat != null:
		_refresh_wave_timer()
	refresh()

func _refresh_wave_timer() -> void:
	var seconds: int = ceili(maxf(0, world.combat.spawner.remaining))
	%WaveTimer.text = tr("ui.hud.wave_timer") % [seconds / 60, seconds % 60]

func _on_time_changed(seconds: int) -> void:
	_timer.text = tr("ui.hud.match_timer") % [seconds / 60, seconds % 60]
	_timer.add_theme_color_override("font_color", ColonyStyle.color(&"danger") if seconds <= PRESENTATION.timer_warning_seconds else ColonyStyle.color(&"accent"))

func set_countdown_visible(enabled: bool) -> void:
	_timer.visible = enabled

func set_zoom(value: int) -> void:
	_zoom_level = value
	_zoom.text = "%sx" % str(WorldCamera.ZOOMS[value])
	controls[&"zoom_in"].disabled = value >= WorldCamera.MAX_LEVEL
	controls[&"zoom_out"].disabled = value <= WorldCamera.MIN_LEVEL

func _refresh_pause_indicator(paused: bool) -> void:
	var manual: bool = PauseController.is_manually_paused()
	%Pause.icon = preload("res://game/assets/ui/build_apply.svg") if manual else preload("res://game/assets/ui/pause.svg")
	%Pause.tooltip_text = "ui.hud.unpause" if manual else "ui.hud.pause"
	%Pause.disabled = paused and not manual

func build_obstacles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	result.append(%MatchStatus.get_global_rect())
	result.append(%MatchControls.get_global_rect())
	result.append(_bottom.get_global_rect())
	if task_panel != null:
		result.append_array(task_panel.visible_bounds())
	elif _objectives.is_visible_in_tree():
		result.append(_objectives.get_global_rect())
	if _task_details.is_visible_in_tree():
		result.append(_task_details.get_global_rect())
	if colony_summary.is_visible_in_tree():
		result.append(colony_summary.get_global_rect())
	if navigation_panel != null and navigation_panel.is_visible_in_tree() and navigation_panel.mouse_filter == Control.MOUSE_FILTER_STOP:
		result.append(navigation_panel.get_global_rect())
	return result

func lock_zoom(locked: bool) -> void:
	_toast.visible = _toast_time > 0.0 and not locked
	controls[&"zoom_in"].disabled = locked or _zoom_level >= WorldCamera.MAX_LEVEL
	controls[&"zoom_out"].disabled = locked or _zoom_level <= WorldCamera.MIN_LEVEL

func toast(message: String, danger: bool = false) -> void:
	_toast.text = message
	_toast.add_theme_color_override("font_color", ColonyStyle.color(&"danger") if danger else ColonyStyle.color(&"text"))
	_toast_time = PRESENTATION.toast_duration
	_toast.show()

func construction_undo_button() -> Button:
	return %Undo

func construction_pan_button() -> Button:
	return %Move

func bottom_bar_height() -> float:
	return _bottom.size.y

func colony_panel_bottom() -> float:
	return colony_summary.get_global_rect().end.y

func set_section(section: StringName) -> void:
	_active_section = section
	%Build.set_pressed_no_signal(section == &"build")
	%ColonyTab.set_pressed_no_signal(section == &"colony")
	%TasksTab.set_pressed_no_signal(section == &"tasks")
	colony_summary.set_expanded(section == &"colony")
	var goals_panel: Control = task_panel if task_panel != null else _objectives
	goals_panel.visible = section == &"tasks"
	if section != &"tasks":
		_task_details.hide()
		set_task_selection(null)
	_toast.hide()

func set_task_selection(order: TaskBuildOrder) -> void:
	if task_panel != null:
		task_panel.set_selection(order)

func set_task_pan_mode(enabled: bool) -> void:
	if task_panel != null:
		task_panel.set_pan_mode(enabled)

func _layout_task_panel() -> void:
	task_panel.dock_above(bottom_bar_height())

func _show_task_details(option: BuildOption) -> void:
	_task_details.toggle(option, world.build_controller, Vector2i(2147483647, 2147483647))
	_task_details.reset_size()

func _request_task_order(task_id: StringName, variant_id: StringName) -> void:
	_task_details.hide()
	order_requested.emit(task_id, variant_id)

func _on_colony_expanded(expanded: bool) -> void:
	if expanded != (_active_section == &"colony"):
		section_requested.emit(&"colony")

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
	for style in [theme.get_stylebox("panel", "PanelContainer"), theme.get_stylebox("panel", "TooltipPanel"), _toast.get_theme_stylebox("normal")]:
		(style as StyleBoxTexture).texture = texture
