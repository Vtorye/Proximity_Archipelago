extends Screen
## Owns presentation, input, and shell integration for exactly one world session.

## Manual check of the end-of-match overlay: enable in the Inspector and start the match.
@export var debug_show_result := false
@export_range(0.0, 600.0, 1.0, "or_greater", "suffix:s") var debug_result_time_left := 83.0
@export var initial_camera_offset := Vector2(0, -8)
var world: World
@onready var camera: WorldCamera = $ColonyCamera
@onready var navigation_overlay: NavigationOverlay = $Navigation
@onready var selection: TileSelection = $Selection
@onready var campaign_panel: CampaignPanel = $Interface/Campaign
@onready var hud: MatchHud = $Interface/Hud
@onready var story: StoryOverlay = $StoryLayer/Story
@onready var chapter: FirstChapter = $Chapter
@onready var conversations: ConversationsMenu = $Interface/Conversations
const CONSTRUCTION_PANEL := preload("res://game/building/ui/construction_menu.tscn")
const NEST_POPUP := preload("res://game/colony/nests/ui/nest_menu.tscn")
const FIRST_ISLAND := preload("res://visual_novel/chapters/first/first_island.tscn")
const ZERO_ISLAND := preload("res://visual_novel/chapters/zero/zero_island.tscn")

var nest_popup: NestMenu
var _construction: ConstructionMenu
var _section: StringName
var _active := false
var _pointer := Vector2(-1, -1)
var _camera_moved := false
var _tutorial_start := false
var _chapter_active := false
var _chapter_checkpoint: Dictionary = {}
var _save_path := SessionSave.PATH
var _follow_actor: Node2D

func _ready() -> void:
	var waves: bool = payload is Dictionary and payload.get("wave_mode", false)
	_tutorial_start = payload is Dictionary and payload.get("tutorial", false) == true
	var snapshot: Dictionary = payload.get("snapshot", {}) if payload is Dictionary else {}
	if payload is Dictionary:
		_save_path = payload.get("save_path", SessionSave.PATH)
	_chapter_checkpoint = snapshot.get("chapter", {})
	if payload is Dictionary and payload.has("tiles"):
		world = LevelLayout.create_world(payload)
	elif _tutorial_start:
		world = (ZERO_ISLAND if payload.get("zero_tutorial", false) else FIRST_ISLAND).instantiate()
	else:
		var seed_generator := RandomNumberGenerator.new()
		seed_generator.randomize()
		var template := LevelLayout.DEFAULT_WORLD.instantiate() as World
		var generated := IslandGenerator.generate_data(template, seed_generator.randi())
		if generated != null:
			world = LevelLayout.instantiate_world(generated)
		if world == null:
			world = template
		else:
			template.free()
	if world == null:
		world = LevelLayout.DEFAULT_WORLD.instantiate()
	if world.chapter_rules is ZeroChapterRules:
		chapter.set_script(ZeroChapter)
		var zero_chapter := chapter as ZeroChapter
		zero_chapter.skip_lessons = payload.get("skip_lessons", false)
		zero_chapter.camera_follow_requested.connect(func(actor: Node2D): _follow_actor = actor)
	_chapter_active = world.chapter_rules != null and (_tutorial_start or not _chapter_checkpoint.is_empty())
	world.waves.enabled = waves or _chapter_active
	world.endless = payload is Dictionary and payload.get("endless", false)
	if world.endless:
		world.match_controller.countdown_enabled = payload.get("queen_timer", false)
	world.name = "World"
	world.auto_start = false
	if _chapter_active:
		world.opening_order = world.chapter_rules.opening_order
	add_child(world)
	move_child(world, 0)
	world.match_controller.completed.connect(_on_completed)
	camera.bounds = world.map_bounds()
	camera.position = camera.bounds.get_center() + initial_camera_offset
	camera.make_current()
	navigation_overlay.configure(world)
	selection.map = world.map
	hud.configure(world, navigation_overlay, camera)
	hud.set_countdown_visible(world.match_controller.countdown_enabled)
	if _chapter_active:
		chapter.configure(world, story)
		chapter.focus_requested.connect(_focus_chapter_cell)
		chapter.checkpoint_requested.connect(_save_chapter_checkpoint)
		chapter.presentation_changed.connect(_refresh_chapter_ui)
		story.modal_changed.connect(_on_story_modal_changed)
		_refresh_chapter_ui()
	if world.voyage != null:
		if payload is Dictionary and payload.has("journey"): world.voyage.apply(payload.journey)
	if payload is Dictionary and payload.has("snapshot"): SessionSave.apply(world, payload.snapshot)
	campaign_panel.configure(world)
	campaign_panel.save_requested.connect(save_game)
	campaign_panel.travel_requested.connect(_travel)
	hud.nest_selected.connect(camera.focus_nest)
	hud.settings_requested.connect(_open_settings)
	hud.navigation_requested.connect(_toggle_navigation)
	hud.construction_requested.connect(_select_section.bind(&"build"))
	hud.order_requested.connect(_begin_royal_order)
	hud.section_requested.connect(_select_section)
	hud.construction_bounds_changed.connect(_update_construction_dock)
	hud.pause_requested.connect(PauseController.toggle_manual)
	hud.speed_requested.connect(_set_simulation_speed)
	hud.zoom_in_requested.connect(func(): camera.set_level(camera.level + 1))
	hud.zoom_out_requested.connect(func(): camera.set_level(camera.level - 1))
	camera.zoom_changed.connect(hud.set_zoom)
	var definitions: FirstChapterRules = world.chapter_rules if _chapter_active else load("res://visual_novel/chapters/first/first_chapter_rules.tres")
	story.characters = definitions.characters
	if not _chapter_active and story.dialogue_resource == null:
		story.dialogue_resource = definitions.dialogue
	conversations.configure(definitions.characters, chapter.topic_available if _chapter_active else Callable())
	conversations.character_selected.connect(_talk_character)
	if _chapter_active:
		camera.zoom_changed.connect(chapter.camera_zoomed)
		camera.panned_by_player.connect(chapter.camera_panned)

func on_focus() -> void:
	_active = true
	world.start()
	if _chapter_active:
		chapter.start(_chapter_checkpoint)
	if payload is Dictionary and (payload.has("journey") or payload.get("save_on_start", false)):
		var error := save_game()
		if error != OK:
			push_warning("Could not save session: %s" % error_string(error))
	if debug_show_result:
		_on_completed(MatchSummary.capture(true, &"target_reached", debug_result_time_left, world.inventory))

func on_blur() -> void:
	Engine.time_scale = 1.0
	story.finish()
	_close_nest_popup()
	_active = false
	world.stop()
	selection.clear()

func _set_simulation_speed(multiplier: float) -> void:
	Engine.time_scale = multiplier

func _on_completed(summary: MatchSummary) -> void:
	if not _active or Router.is_navigating():
		return
	selection.clear()
	story.finish()
	if world.voyage != null and world.voyage.departed: return
	if Router.push_overlay(&"match_result", summary) != null:
		PauseController.acquire(&"result")

func _input(event: InputEvent) -> void:
	if not _active or Router.is_navigating():
		return
	if story.is_modal or is_instance_valid(_follow_actor):
		camera.dragging = false
		return
	if event is InputEventMouseMotion: _pointer = event.position
	var top: MenuBase = Router.top_overlay()
	if top != null or _building_active():
		camera.dragging = false
	if top == null and event.is_action_pressed(&"ui_cancel") and _dismiss_visible_nest_popup():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		if event.pressed:
			_camera_moved = false
		elif camera.dragging:
			camera.dragging = false
			if event.button_index == MOUSE_BUTTON_LEFT and not _camera_moved:
				_inspect_building(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and camera.dragging:
		_camera_moved = _camera_moved or not event.relative.is_zero_approx()
		camera.pan(event.relative)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_navigation") and _navigation_available():
		_toggle_navigation()
		get_viewport().set_input_as_handled()
		return
	if top == null and event is InputEventKey and event.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		get_viewport().set_input_as_handled()
		return

func _unhandled_input(event: InputEvent) -> void:
	if not _active or Router.is_navigating() or story.is_modal or is_instance_valid(_follow_actor): return
	var top: MenuBase = Router.top_overlay()
	if top == null and event.is_action_pressed(&"ui_cancel") and not _building_active() and not campaign_panel.visible:
		_open_settings()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (top is PauseMenu or (top == null and not _building_active())):
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_inspect_secondary_cell(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_inspect_building(_cell_at(event.position))
			get_viewport().set_input_as_handled()
			return
	if top == null:
		for section: StringName in [&"build", &"colony", &"tasks"]:
			if event.is_action_pressed("open_" + section) and (not _chapter_active or chapter.shows_control(section)):
				_select_section(section)
				get_viewport().set_input_as_handled()
				return

func _process(_delta: float) -> void:
	if camera == null:
		return
	var top: MenuBase = Router.top_overlay()
	if is_instance_valid(_follow_actor):
		camera.global_position = _follow_actor.global_position
		camera.force_update_scroll()
	story.set_covered(top != null or campaign_panel.visible)
	var can_use_map: bool = top == null and not story.is_modal and not campaign_panel.visible
	if is_instance_valid(_construction):
		_construction.visible = can_use_map and _section != &"talk"
	hud.set_construction_controls_visible(_building_active())
	conversations.visible = can_use_map and _section == &"talk"
	conversations.dock_above(hud.bottom_bar_height())
	camera.enabled_input = can_use_map and not _building_active() and not is_instance_valid(_follow_actor)
	if is_instance_valid(nest_popup):
		nest_popup.visible = (top == null or top is PauseMenu) and not story.is_modal and not campaign_panel.visible
		$PopupLayer.layer = 8
	hud.lock_zoom(top != null or story.is_modal)
	hud.highlight_control(chapter.highlighted_control() if _chapter_active and not story.is_modal else &"")
	if _chapter_active:
		if can_use_map:
			var map_area := world.map.get_used_rect()
			selection.show_guides(chapter.guide_cells().filter(func(cell: Vector2i): return map_area.has_point(cell)))
		elif selection.selected:
			selection.clear()
	elif navigation_overlay.mode == 2 and _navigation_available():
		if not selection.selected or selection.cell != navigation_overlay.origin: selection.select(navigation_overlay.origin)
	elif _navigation_available() and hud.navigation_panel.inspected_cell != null:
		var cell: Vector2i = hud.navigation_panel.inspected_cell
		if not selection.selected or selection.cell != cell: selection.select(cell)
	elif selection.selected: selection.clear()
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	var panel: NavigationPanel = hud.navigation_panel
	if hovered_control == null or (hovered_control != panel and not panel.is_ancestor_of(hovered_control)):
		navigation_overlay.hover_active = _navigation_available() and hovered_control == null and get_viewport_rect().has_point(_pointer)
		if navigation_overlay.hover_active or not panel.is_visible_in_tree():
			navigation_overlay.hovered = _cell_at(_pointer)

func _refresh_chapter_ui() -> void:
	hud.set_tutorial_controls(chapter)
	_close_nest_popup()
	hud.navigation_panel.inspect_cell(null)
	hud.set_countdown_visible(chapter.countdown_visible())
	hud.set_economy_visible(true)
	hud.get_node("%WaveTimer").hide()
	if is_instance_valid(_construction):
		_close_construction_panel(_construction)
	hud.set_section(&"")
	_section = &""

func _focus_chapter_cell(cell: Vector2i) -> void:
	# Let native containers settle before choosing a clear map point between windows.
	await get_tree().process_frame
	var viewport_size := get_viewport_rect().size
	var preferred := viewport_size * chapter.rules.camera_focus_ratio
	var bounds := _construction_obstacles()
	if is_instance_valid(_construction):
		bounds.append_array(_construction.visible_bounds())
	var clearance: float = world.route_service.cell_size() * camera.zoom.x * 0.5
	var xs: Array[float] = [preferred.x, viewport_size.x * 0.5]
	var ys: Array[float] = [preferred.y, viewport_size.y * 0.5]
	for obstacle in bounds:
		xs.append(obstacle.position.x - clearance)
		xs.append(obstacle.end.x + clearance)
		ys.append(obstacle.position.y - clearance)
		ys.append(obstacle.end.y + clearance)
	var target := preferred
	var closest := INF
	var view := Rect2(Vector2.ZERO, viewport_size).grow(-clearance)
	for x in xs:
		for y in ys:
			var candidate := Vector2(x, y).round()
			if not view.has_point(candidate) or bounds.any(func(rect: Rect2) -> bool: return rect.grow(clearance * 0.5).has_point(candidate)):
				continue
			var distance := candidate.distance_squared_to(preferred)
			if distance < closest:
				closest = distance
				target = candidate
	camera.position = world.route_service.cell_to_world(cell) + (viewport_size * 0.5 - target) / camera.zoom
	camera.force_update_scroll()

func _talk_character(character: StoryCharacter) -> void:
	if story.is_modal or Router.has_overlay():
		return
	conversations.hide()
	_section = &""
	hud.set_section(&"")
	if _chapter_active:
		chapter.talk(character)
	else:
		story.play(str(character.topic))

func _on_story_modal_changed(modal: bool) -> void:
	if modal:
		hud.navigation_panel.inspect_cell(null)
		_close_nest_popup()
		camera.dragging = false
		camera.enabled_input = false
		if is_instance_valid(_construction):
			_construction.hide()
		if is_instance_valid(nest_popup):
			nest_popup.hide()

func _travel(layout: Dictionary) -> void:
	layout["save_path"] = _save_path
	Router.goto(&"match", layout)

func _checkpoint_path() -> String:
	return FirstChapter.CHECKPOINT if _save_path == SessionSave.PATH else _save_path.get_basename() + ".checkpoint"

func _save_chapter_checkpoint(path: String) -> void:
	save_game(_checkpoint_path() if path == FirstChapter.CHECKPOINT else "")

func save_game(path := "") -> Error:
	return SessionSave.write(world, _save_path if path.is_empty() else path, {}, path.is_empty() and world.voyage != null)

func retry_game() -> void:
	var saved := SessionSave.read(_checkpoint_path()) if _chapter_active else {}
	if not saved.is_empty():
		var layout: Dictionary = saved.layout.duplicate()
		layout["snapshot"] = saved
		layout["save_path"] = _save_path
		Router.goto(&"match", layout)
	else:
		Router.restart_current()

func _cell_at(point: Vector2) -> Vector2i:
	var map: TileMapLayer = world.map
	return map.local_to_map(map.get_global_transform_with_canvas().affine_inverse() * point)

func _inspect_building(cell: Vector2i) -> void:
	if _chapter_active and not chapter.nest_available():
		story.flash_warning("ui.chapter.nest_secret")
		return
	var building: Building = world.registry.at(cell)
	if _chapter_active and building is CargoShip:
		if chapter.can_evacuate():
			chapter.evacuate()
		else:
			story.flash_warning("ui.chapter.ship_not_ready")
		return
	hud.navigation_panel.inspect_cell(cell)
	if (building is House or building is Canteen) and world.logistics.owns(building):
		camera.dragging = false
		if Router.top_overlay() == null:
			_open_nest_popup(building)

func _open_nest_popup(building: Building) -> void:
	camera.clear_nest_focus()
	_close_nest_popup()
	var popup: NestMenu = NEST_POPUP.instantiate()
	popup.payload = {"world": world, "building": building}
	popup.close_requested.connect(func(_menu: MenuBase): _dismiss_visible_nest_popup())
	nest_popup = popup
	$PopupLayer/NestPopups.add_child(popup)

func _dismiss_visible_nest_popup() -> bool:
	if not is_instance_valid(nest_popup) or not nest_popup.is_visible_in_tree():
		return false
	_close_nest_popup()
	hud.navigation_panel.inspect_cell(null)
	return true

func _close_nest_popup() -> void:
	if is_instance_valid(nest_popup):
		nest_popup.hide()
		nest_popup.queue_free()
	nest_popup = null

func _inspect_secondary_cell(cell: Vector2i) -> void:
	if navigation_overlay.mode == 2:
		navigation_overlay.select_origin(cell)
	_inspect_building(cell)

func _open_settings() -> void:
	if story.is_modal or campaign_panel.visible or Router.has_overlay():
		return
	hud.navigation_panel.inspect_cell(null)
	selection.clear()
	if Router.push_overlay(&"pause") != null:
		PauseController.acquire(&"menu")

func _select_section(section: StringName) -> void:
	if story.is_modal or Router.has_overlay() or campaign_panel.visible:
		return
	if _chapter_active and not chapter.allows_section(section):
		hud.set_section(_section)
		chapter.reprimand()
		return
	var already_open := _section == section
	if section == &"build" and is_instance_valid(_construction):
		already_open = _section == &"build" and _construction.is_palette_open()
	_section = &"" if already_open else section
	if _section in [&"build", &"tasks"]:
		hud.navigation_panel.inspect_cell(null)
	hud.set_section(_section)
	if _section == &"build":
		if not is_instance_valid(_construction):
			_create_construction_panel()
		_construction.show_catalog(chapter.preferred_option() if _chapter_active else &"")
		camera.dragging = false
		camera.enabled_input = false
		selection.clear()
	elif _section == &"tasks" and is_instance_valid(_construction):
		_construction.select_order()
		hud.set_task_selection(null)
	elif is_instance_valid(_construction):
		_construction.set_palette_visible(false)

func _create_construction_panel() -> void:
	var context := ConstructionContext.new()
	context.controller = world.build_controller
	context.art = world.art
	context.camera = camera
	context.undo_button = hud.construction_undo_button()
	context.apply_button = hud.construction_apply_button()
	context.pan_button = hud.construction_pan_button()
	context.obstacles = _construction_obstacles
	context.dismiss_map_popup = _dismiss_visible_nest_popup
	if hud.task_panel != null:
		context.task_bounds = hud.task_panel.visible_bounds
	if _chapter_active:
		context.allow_tool = chapter.allows_tool
	_construction = CONSTRUCTION_PANEL.instantiate()
	_construction.payload = context
	_construction.map_inspection_requested.connect(_inspect_secondary_cell)
	_construction.pan_mode_changed.connect(hud.set_task_pan_mode)
	if _chapter_active:
		_construction.restricted_action.connect(chapter.reprimand)
	_construction.placement_drafted.connect(story.clear_reprimand)
	_construction.draft_pricing_changed.connect(hud.set_draft_prices)
	_construction.close_requested.connect(_close_construction_panel)
	$ConstructionLayer.add_child(_construction)
	_update_construction_dock()

func _begin_royal_order(task_id: StringName, variant_id: StringName) -> void:
	if story.is_modal:
		return
	if _chapter_active and not chapter.allows_order(task_id, variant_id):
		chapter.reprimand()
		return
	var order := world.tasks.start_order(task_id, variant_id)
	if order == null:
		return
	if not is_instance_valid(_construction):
		_create_construction_panel()
	_section = &"tasks"
	hud.set_section(_section)
	_construction.select_order(order)
	hud.set_task_selection(order)
	if _chapter_active:
		_focus_chapter_cell(chapter.guide_cell())
	camera.dragging = false
	camera.enabled_input = false
	selection.clear()

func _close_construction_panel(menu: MenuBase) -> void:
	if menu != _construction:
		return
	_construction.hide()
	_construction.detach_toolbar()
	_construction.queue_free()
	_construction = null
	hud.set_draft_prices({})
	hud.set_task_selection(null)
	hud.set_task_pan_mode(false)
	if _section != &"tasks":
		_section = &""
	hud.set_section(_section)

func _building_active() -> bool:
	return is_instance_valid(_construction) and _construction.visible

func _update_construction_dock() -> void:
	if is_instance_valid(_construction):
		_construction.dock_between(hud.bottom_bar_height(), hud.colony_panel_bottom())

func _construction_obstacles() -> Array[Rect2]:
	var obstacles: Array[Rect2] = hud.build_obstacles()
	if conversations.is_visible_in_tree():
		obstacles.append(conversations.panel_bounds())
	var hint_bounds := story.hint_bounds()
	if hint_bounds.has_area():
		obstacles.append(hint_bounds)
	if is_instance_valid(nest_popup) and nest_popup.is_visible_in_tree():
		obstacles.append(nest_popup.panel_bounds())
	return obstacles

func _navigation_available() -> bool:
	var top: MenuBase = Router.top_overlay()
	return _active and not story.is_modal and not Router.is_navigating() and (top == null or top is PauseMenu) and (not _chapter_active or chapter.shows_control(&"routes"))

func _toggle_navigation() -> void:
	if not _navigation_available(): return
	if _chapter_active and not chapter.economy_visible():
		hud.set_navigation_mode(navigation_overlay.mode)
		chapter.reprimand()
		return
	navigation_overlay.cycle()
	if _chapter_active:
		chapter.navigation_changed(navigation_overlay.mode)
	hud.set_navigation_mode(navigation_overlay.mode)
	if Router.has_overlay(): return
	var messages: Array[String] = [
		tr("ui.nav.hidden"),
		tr("ui.nav.entry_help") % navigation_overlay.reference_speed,
		tr("ui.nav.routes_help") % world.planner.load_penalty_seconds,
	]
	hud.toast(messages[navigation_overlay.mode])
