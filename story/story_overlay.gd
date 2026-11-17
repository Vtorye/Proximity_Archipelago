extends Control
class_name StoryOverlay

signal modal_changed(is_modal: bool)

const PAUSE_REASON := &"tutorial_dialogue"
const ROAD := "road"
const ORDER := "order"

@export var episode: StoryEpisode

var is_modal := false
var _active := false
var _covered := false
var _loading := false
var _cue := ""
var _road_complete := false
var _order_variant := ""
var _line: DialogueLine

@onready var _shade: ColorRect = %Shade
@onready var _dialogue_panel: PanelContainer = %DialoguePanel
@onready var _speaker: Label = %Speaker
@onready var _dialogue: Label = %Dialogue
@onready var _portrait: TextureRect = %Portrait
@onready var _continue: Button = %Continue
@onready var _hint_panel: PanelContainer = %HintPanel
@onready var _hint: Label = %Hint

func _ready() -> void:
	_continue.pressed.connect(_advance)
	for button: Button in [%SkipDialogue, %SkipHint, _continue]:
		button.pressed.connect(AppSettings.play_click)
	%SkipDialogue.pressed.connect(finish)
	%SkipHint.pressed.connect(finish)
	hide()

func start(checkpoint: Dictionary) -> void:
	_active = true
	_road_complete = checkpoint.get("road_complete", false) == true
	var variant: Variant = checkpoint.get("order_variant", "")
	if variant is String and episode.opening_order.variant_by_id(StringName(variant)) != null:
		_order_variant = variant
	var cue: Variant = checkpoint.get("cue", "")
	_set_modal(true)
	_request_line(cue if cue in [ROAD, ORDER] else "intro")

func capture_checkpoint() -> Dictionary:
	if not _active:
		return {}
	return {"cue": _cue, "road_complete": _road_complete, "order_variant": _order_variant}

func set_covered(covered: bool) -> void:
	if _covered != covered:
		_covered = covered
		_refresh_visibility()

func hint_bounds() -> Rect2:
	return _hint_panel.get_global_rect() if _hint_panel.is_visible_in_tree() else Rect2()

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
		finish()
		return
	_line = next
	_cue = _line.get_tag_value("action")
	if not _cue.is_empty():
		_hint.text = _line.text
		_set_modal(false)
		return
	_speaker.text = "ui.story.queen" if _line.character == "Queen" else "ui.story.protagonist"
	_dialogue.text = _line.text
	%Scroll.scroll_vertical = 0
	var portrait_path := _line.get_tag_value("portrait")
	_portrait.texture = load(portrait_path) as Texture2D if not portrait_path.is_empty() else null
	_continue.disabled = false
	_set_modal(true)

func _advance() -> void:
	if is_modal and _line != null:
		_request_line(_line.next_id)

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
	_hint_panel.visible = not is_modal
	if not visible:
		return
	if is_modal:
		if not _continue.disabled:
			_continue.grab_focus()
	else:
		_advance_checkpoint.call_deferred()

func finish() -> void:
	if not _active:
		return
	_active = false
	_set_modal(false)

func _exit_tree() -> void:
	if is_modal:
		PauseController.release(PAUSE_REASON)
