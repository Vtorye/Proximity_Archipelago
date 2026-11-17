extends Control
class_name StoryOverlay

signal modal_changed(is_modal: bool)
signal finished

const PAUSE_REASON := &"tutorial_dialogue"
const ROAD := "road"
const ORDER := "order"

@export var episode: StoryEpisode
@export_range(10.0, 100.0, 1.0) var characters_per_second := 45.0
@export_range(0.0, 24.0, 1.0) var portrait_bob_height := 8.0
@export_range(0.05, 0.5, 0.01) var portrait_bob_seconds := 0.22
@export_range(0.5, 2.0, 0.01) var queen_pitch := 0.93
@export_range(0.5, 2.0, 0.01) var steward_pitch := 1.24
@export_range(0.05, 0.6, 0.01) var name_swipe_seconds := 0.24

var is_modal := false
var _active := false
var _covered := false
var _loading := false
var _cue := ""
var _road_complete := false
var _order_variant := ""
var _first_reprimand_seen := false
var _interrupted_cue := ""
var _line: DialogueLine
var _hint_key := ""
var _warning_key := ""
var _waiting := false
var _spoken_text := ""
var _characters_revealed := 0.0
var _portrait_tween: Tween
var _name_tween: Tween
var _name_dismissing := false

@onready var _shade: ColorRect = %Shade
@onready var _dialogue_panel: PanelContainer = %DialoguePanel
@onready var _speaker: Label = %Speaker
@onready var _dialogue: Label = %Dialogue
@onready var _portrait: TextureRect = %Portrait
@onready var _continue: Button = %Continue
@onready var _hint_panel: PanelContainer = %HintPanel
@onready var _hint: Label = %Hint
@onready var _warning: Timer = %Warning
@onready var _voice: AudioStreamPlayer = %Voice
@onready var _name_window: Control = %NameWindow
@onready var _name_input: LineEdit = %NameInput

func _ready() -> void:
	_continue.pressed.connect(_advance)
	for button: Button in [%SkipDialogue, %SkipHint, _continue]:
		button.pressed.connect(AppSettings.play_click)
	%SkipDialogue.pressed.connect(finish)
	%SkipHint.pressed.connect(finish)
	_warning.timeout.connect(_clear_warning)
	_name_input.text_changed.connect(_on_name_changed)
	set_process(false)
	hide()

func start(checkpoint: Dictionary) -> void:
	_active = true
	_road_complete = checkpoint.get("road_complete", false) == true
	_first_reprimand_seen = checkpoint.get("first_reprimand_seen", false) == true
	var variant: Variant = checkpoint.get("order_variant", "")
	if variant is String and episode.opening_order.variant_by_id(StringName(variant)) != null:
		_order_variant = variant
	var cue: Variant = checkpoint.get("cue", "")
	_set_modal(true)
	_request_line(cue if cue in [ROAD, ORDER] else "intro")

func capture_checkpoint() -> Dictionary:
	if not _active:
		return {}
	return {
		"cue": _cue if _interrupted_cue.is_empty() else _interrupted_cue,
		"road_complete": _road_complete,
		"order_variant": _order_variant,
		"first_reprimand_seen": _first_reprimand_seen,
	}

func set_covered(covered: bool) -> void:
	if _covered != covered:
		_covered = covered
		_refresh_visibility()

func hint_bounds() -> Rect2:
	return _hint_panel.get_global_rect() if _hint_panel.is_visible_in_tree() else Rect2()

func is_active() -> bool:
	return _active

func guide_section() -> StringName:
	if not _active or is_modal:
		return &""
	match _cue:
		ROAD: return &"build"
		ORDER: return &"tasks"
	return &""

func guide_cell() -> Vector2i:
	return episode.road_cell if _cue == ROAD else episode.order_cell

func allows_order(task_id: StringName) -> bool:
	return not _active or (guide_section() == &"tasks" and task_id == episode.opening_order.id)

func allows_tool(option: BuildOption, order: TaskBuildOrder) -> bool:
	if not _active:
		return true
	if option == null:
		return false
	match guide_section():
		&"build": return order == null and option == episode.road_option
		&"tasks": return order != null and order.task == episode.opening_order
	return false

func allows_placement(option: BuildOption, cell: Vector2i, order: TaskBuildOrder) -> bool:
	return not _active or (cell == guide_cell() and allows_tool(option, order))

func set_waiting_for_workers(waiting: bool) -> void:
	if _waiting != waiting:
		_waiting = waiting
		_clear_warning()

func reprimand(reason: StringName = &"action") -> void:
	if not _active or is_modal or _covered:
		return
	if not _first_reprimand_seen:
		_show_first_reprimand.call_deferred()
		return
	var key := "ui.story.guided.cell"
	if _waiting:
		key = "ui.story.guided.impatient"
	elif reason != &"cell":
		key = "ui.story.guided.road_only" if _cue == ROAD else "ui.story.guided.order_only"
	if _warning_key == key and not _warning.is_stopped():
		return
	_warning_key = key
	_hint.text = key
	_hint.add_theme_color_override(&"font_color", ColonyStyle.color(&"accent"))
	_voice.pitch_scale = queen_pitch
	_voice.play()
	_warning.start()

func _show_first_reprimand() -> void:
	if _first_reprimand_seen or _loading or _covered or guide_section().is_empty():
		return
	_first_reprimand_seen = true
	_interrupted_cue = _cue
	_set_modal(true)
	_request_line("first_reprimand")

func clear_reprimand() -> void:
	if not _warning_key.is_empty():
		_clear_warning()

func _clear_warning() -> void:
	_warning.stop()
	_warning_key = ""
	_hint.remove_theme_color_override(&"font_color")
	_hint.text = "ui.story.guided.wait" if _waiting else _hint_key

func on_build_completed(option: BuildOption, _cell: Vector2i) -> void:
	if _active and not _road_complete and option.placement_kind == BuildOption.PlacementKind.ROAD:
		_road_complete = true
		_advance_checkpoint.call_deferred()

func on_order_completed(order: TaskBuildOrder) -> void:
	if _active and order.task == episode.opening_order and _order_variant.is_empty():
		_order_variant = String(order.variant.id)
		_advance_checkpoint.call_deferred()

func _request_line(id: String) -> void:
	if not _active or _loading:
		return
	_loading = true
	_continue.disabled = true
	var next := await episode.dialogue.get_next_dialogue_line(id)
	_loading = false
	if not _active or not is_inside_tree():
		return
	if next == null:
		if _interrupted_cue.is_empty():
			finish()
		else:
			_cue = _interrupted_cue
			_interrupted_cue = ""
			_set_modal(false)
		return
	_line = next
	_cue = _line.get_tag_value("action")
	if not _cue.is_empty():
		_hint_key = _line.text
		_waiting = false
		_clear_warning()
		_set_modal(false)
		return
	var queen := _line.character == "Queen"
	_speaker.text = "ui.story.queen" if queen else "ui.story.protagonist"
	_voice.pitch_scale = queen_pitch if queen else steward_pitch
	_spoken_text = tr(_line.text)
	_dialogue.text = _spoken_text
	_dialogue.visible_characters = 0
	_characters_revealed = 0.0
	set_process(true)
	%Scroll.scroll_vertical = 0
	var portrait_path := _line.get_tag_value("portrait")
	var texture := load(portrait_path) as Texture2D if not portrait_path.is_empty() else null
	if texture != _portrait.texture:
		_portrait.texture = texture
		_bob_portrait()
	_continue.disabled = false
	_set_modal(true)

func _advance() -> void:
	if is_modal and _line != null and not _name_window.visible:
		if _dialogue.visible_characters != -1:
			_reveal_line()
			return
		_request_line(_line.next_id)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not is_modal:
		return
	var previous := _dialogue.visible_characters
	_characters_revealed += delta * characters_per_second
	var next := mini(int(_characters_revealed), _spoken_text.length())
	_dialogue.visible_characters = next
	for index in range(previous, next):
		if index % 2 == 0 and not _spoken_text[index] in " \t\n.,!?…:;—«»'":
			_voice.play()
			break
	if next == _spoken_text.length():
		_dialogue.visible_characters = -1
		set_process(false)
		_show_name_input()

func _reveal_line() -> void:
	set_process(false)
	_dialogue.visible_characters = -1
	_voice.stop()
	_show_name_input()

func _show_name_input() -> void:
	if not _active or _line == null or not _line.has_tag("name_input") or _name_window.visible:
		return
	_name_window.show()
	_continue.disabled = true
	_name_input.grab_focus()

func _on_name_changed(value: String) -> void:
	if value.is_empty() or _name_dismissing or not _active:
		return
	_name_dismissing = true
	_name_input.editable = false
	_name_input.release_focus()
	_name_tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_name_tween.tween_property(_name_window, "position:x", get_viewport_rect().size.x, name_swipe_seconds)
	_name_tween.tween_property(_name_window, "modulate:a", 0.0, name_swipe_seconds)
	await _name_tween.finished
	if not _active:
		return
	_name_window.hide()
	_name_input.clear()
	_request_line(_line.next_id)

func _bob_portrait() -> void:
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	_portrait.position.y = 0.0
	_portrait_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_portrait_tween.tween_property(_portrait, "position:y", -portrait_bob_height, portrait_bob_seconds * 0.4).set_ease(Tween.EASE_OUT)
	_portrait_tween.tween_property(_portrait, "position:y", 0.0, portrait_bob_seconds * 0.6).set_ease(Tween.EASE_IN_OUT)

func _advance_checkpoint() -> void:
	if not _active or is_modal or _covered or _loading:
		return
	if _cue == ROAD and _road_complete:
		_request_line("after_road")
	elif _cue == ORDER and not _order_variant.is_empty():
		_request_line("ending_" + _order_variant)

func _set_modal(enabled: bool) -> void:
	if is_modal != enabled:
		is_modal = enabled
		if enabled:
			PauseController.acquire(PAUSE_REASON)
		else:
			PauseController.release(PAUSE_REASON)
		modal_changed.emit(enabled)
	_refresh_visibility()

func _refresh_visibility() -> void:
	visible = _active and not _covered
	_shade.visible = is_modal
	_dialogue_panel.visible = is_modal
	%PortraitMount.visible = is_modal
	_hint_panel.visible = not is_modal
	if not visible:
		return
	if is_modal:
		if _name_window.visible and not _name_dismissing:
			_name_input.grab_focus()
		elif not _continue.disabled:
			_continue.grab_focus()
	else:
		_advance_checkpoint.call_deferred()

func finish() -> void:
	if not _active:
		return
	_active = false
	if _name_tween != null and _name_tween.is_valid():
		_name_tween.kill()
	_name_window.hide()
	_name_input.clear()
	_warning.stop()
	_reveal_line()
	_set_modal(false)
	finished.emit()

func _exit_tree() -> void:
	if is_modal:
		PauseController.release(PAUSE_REASON)
