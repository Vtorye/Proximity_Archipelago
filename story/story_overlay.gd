extends Control
class_name StoryOverlay
## Dialogue presentation. Chapter progression and gameplay permissions belong to FirstChapter.

signal modal_changed(is_modal: bool)
signal scene_finished
signal action_requested(action: StringName)
signal practice_done_requested
const PAUSE_REASON := &"tutorial_dialogue"

@export var dialogue_resource: DialogueResource
@export_range(10.0, 150.0, 1.0) var characters_per_second := 45.0
@export_range(0.0, 24.0, 1.0) var portrait_bob_height := 8.0
@export_range(0.05, 0.5, 0.01) var portrait_bob_seconds := 0.22
@export_range(0.05, 0.6, 0.01) var name_swipe_seconds := 0.24
@export var dialogue_inset := Vector2(12, 12)
@export_range(0.3, 1.0, 0.05) var dialogue_max_height_ratio := 0.9
@export_range(32.0, 200.0, 1.0) var dialogue_min_text_height := 88.0
@export_range(0.0, 80.0, 1.0) var portrait_protrusion := 24.0
@export_range(0.0, 32.0, 1.0) var portrait_bottom_inset := 3.0
var characters: Array[StoryCharacter] = []
var is_modal := false
var _active := false
var _covered := false
var _loading := false
var _line: DialogueLine
var _hint_key := ""
var _warning_key := ""
var _spoken_text := ""
var _characters_revealed := 0.0
var _line_speed := 45.0
var _portrait_tween: Tween
var _name_tween: Tween
var _name_dismissing := false
var _dialogue_layout_pending := false

@onready var _shade: ColorRect = %Shade
@onready var _dialogue_panel: PanelContainer = %DialoguePanel
@onready var _dialogue_header: WindowHeader = %DialogueHeader
@onready var _dialogue: Label = %Dialogue
@onready var _dialogue_scroll: ScrollContainer = %Scroll
@onready var _dialogue_text: VBoxContainer = %Text
@onready var _dialogue_contents: VBoxContainer = %DialogueContents
@onready var _dialogue_actions: HBoxContainer = %DialogueActions
@onready var _portrait: TextureRect = %Portrait
@onready var _continue: Button = %Continue
@onready var _hint_panel: PanelContainer = %HintPanel
@onready var _hint: Label = %Hint
@onready var _warning: Timer = %Warning
@onready var _voice: AudioStreamPlayer = %Voice
@onready var _name_window: Control = %NameWindow
@onready var _name_input: LineEdit = %NameInput

func _ready() -> void:
	%DialogueHeader.collapsed_changed.connect(func(_collapsed: bool):
		_layout_dialogue()
		_refresh_visibility())
	_dialogue_panel.minimum_size_changed.connect(_queue_dialogue_layout)
	_dialogue.minimum_size_changed.connect(_queue_dialogue_layout)
	_dialogue.resized.connect(_queue_dialogue_layout)
	get_viewport().size_changed.connect(_queue_dialogue_layout)
	AppSettings.text_size_changed.connect(_queue_dialogue_layout)
	_continue.pressed.connect(_advance)
	for button: Button in [%SkipDialogue, _continue]:
		button.pressed.connect(AppSettings.play_click)
	%SkipDialogue.pressed.connect(_skip_scene)
	%SkipHint.hide()
	%PracticeDone.pressed.connect(AppSettings.play_click)
	%PracticeDone.pressed.connect(practice_done_requested.emit)
	_warning.timeout.connect(_clear_warning)
	_name_input.text_changed.connect(_on_name_changed)
	set_process(false)
	hide()

func _queue_dialogue_layout() -> void:
	if not _dialogue_layout_pending:
		_dialogue_layout_pending = true
		_layout_dialogue.call_deferred()

func _layout_dialogue() -> void:
	_dialogue_layout_pending = false
	var window: Control = %DialogueWindow
	var viewport_size := get_viewport_rect().size
	window.size.x = viewport_size.x - dialogue_inset.x * 2.0
	if not _dialogue_header.collapsed:
		var chrome := _dialogue_panel.get_theme_stylebox(&"panel").get_minimum_size().y
		chrome += _dialogue_header.get_combined_minimum_size().y + _dialogue_actions.get_combined_minimum_size().y
		chrome += _dialogue_contents.get_theme_constant(&"separation") + _dialogue_text.get_theme_constant(&"separation")
		var height_limit := minf(viewport_size.y * dialogue_max_height_ratio, viewport_size.y - dialogue_inset.y * 2.0)
		# Native Label shaping measures the whole wrapped line, including unrevealed letters.
		_dialogue_scroll.custom_minimum_size.y = minf(maxf(dialogue_min_text_height, _dialogue.get_minimum_size().y), maxf(0.0, height_limit - chrome))
	window.size.y = _dialogue_panel.get_combined_minimum_size().y
	%DialogueHeader.place(Vector2(dialogue_inset.x, get_viewport_rect().size.y - window.size.y - dialogue_inset.y))
	var mount: Control = %PortraitMount
	var portrait_top := window.size.y - mount.size.y - portrait_bottom_inset
	if _portrait.texture != null:
		var texture_size := _portrait.texture.get_size()
		var drawn_height := texture_size.y * minf(mount.size.x / texture_size.x, mount.size.y / texture_size.y)
		var letterbox := (mount.size.y - drawn_height) * 0.5
		portrait_top = minf(portrait_top, -portrait_protrusion - letterbox)
	mount.position.y = maxf(portrait_top, -window.position.y)

func play(title: String) -> void:
	if _loading:
		return
	_active = true
	_warning.stop()
	_set_modal(true)
	_request_line(title)

func show_hint(key: String) -> void:
	_active = true
	_hint_key = key
	_clear_warning()
	%HintHeader.queue_layout()
	_refresh_visibility()

func set_practice_done(shown: bool, enabled: bool) -> void:
	%PracticeDone.visible = shown
	%PracticeDone.disabled = not enabled
	%HintHeader.queue_layout()

func set_covered(covered: bool) -> void:
	if _covered != covered:
		_covered = covered
		_refresh_visibility()

func hint_bounds() -> Rect2:
	return _hint_panel.get_global_rect() if _hint_panel.is_visible_in_tree() else Rect2()

func flash_warning(key: String) -> void:
	if is_modal or _covered or _warning_key == key and not _warning.is_stopped():
		return
	_warning_key = key
	_hint.text = key
	_hint.add_theme_color_override(&"font_color", ColonyStyle.color(&"accent"))
	_voice.play()
	_warning.start()

func clear_reprimand() -> void:
	if not _warning_key.is_empty():
		_clear_warning()

func _clear_warning() -> void:
	_warning.stop()
	_warning_key = ""
	_hint.remove_theme_color_override(&"font_color")
	_hint.text = _hint_key

func _request_line(id: String, skip := false) -> void:
	if not _active or _loading:
		return
	if dialogue_resource == null:
		push_error("StoryOverlay requires a DialogueResource. Assign it in the Inspector or configure the chapter before play().")
		finish()
		return
	_loading = true
	_continue.disabled = true
	var next := await dialogue_resource.get_next_dialogue_line(id)
	while skip and next != null and next.get_tag_value("action").is_empty():
		next = await dialogue_resource.get_next_dialogue_line(next.next_id)
	_loading = false
	if not _active or not is_inside_tree():
		return
	if next == null:
		_set_modal(false)
		scene_finished.emit()
		return
	_line = next
	var action := _line.get_tag_value("action")
	if not action.is_empty():
		_set_modal(false)
		action_requested.emit(StringName(action))
		return
	var character: StoryCharacter
	for definition in characters:
		if str(definition.id) == _line.character:
			character = definition
			break
	_dialogue_header.set_title(character.display_name if character != null else _line.character)
	%DialogueHeader.set_collapsed(false)
	_voice.pitch_scale = character.voice_pitch if character != null else 1.0
	_line_speed = character.characters_per_second if character != null else characters_per_second
	_spoken_text = tr(_line.text)
	_dialogue.text = _spoken_text
	_dialogue.visible_characters = 0
	_characters_revealed = 0.0
	set_process(true)
	%Scroll.scroll_vertical = 0
	var portrait_path := _line.get_tag_value("portrait")
	var texture := load(portrait_path) as Texture2D if not portrait_path.is_empty() else (character.portrait if character != null else null)
	_portrait.self_modulate = Color(1.0, 0.6, 0.55) if _line.character == "Planner" else Color.WHITE
	%PaperHat.visible = _line.character == "Planner"
	if texture != _portrait.texture:
		_portrait.texture = texture
		_bob_portrait()
	_continue.disabled = false
	_set_modal(true)

func _skip_scene() -> void:
	if is_modal and _line != null and not _loading:
		_close_name_input()
		_request_line(_line.next_id, true)

func _advance() -> void:
	if is_modal and _line != null and not _name_window.visible:
		if _dialogue.visible_characters != -1:
			_reveal_line()
		else:
			_request_line(_line.next_id)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not is_modal:
		return
	var previous := _dialogue.visible_characters
	_characters_revealed += delta * _line_speed
	var next := mini(int(_characters_revealed), _spoken_text.length())
	_dialogue.visible_characters = next
	for index in range(previous, next):
		if index % 2 == 0 and not _spoken_text[index] in " \t\n.,!?…:;—«»'":
			_voice.play()
			break
	if next == _spoken_text.length():
		_reveal_line()

func _reveal_line() -> void:
	set_process(false)
	_dialogue.visible_characters = -1
	_voice.stop()
	if _active and _line != null and _line.has_tag("name_input") and not _name_window.visible:
		_name_dismissing = false
		_name_window.modulate.a = 1.0
		_name_input.editable = true
		%NameHeader.set_collapsed(false)
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
	if _active:
		_name_window.hide()
		_name_input.clear()
		_request_line(_line.next_id)

func _close_name_input() -> void:
	if _name_tween != null and _name_tween.is_valid():
		_name_tween.kill()
	_name_window.hide()
	_name_input.clear()

func _bob_portrait() -> void:
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	_portrait.position.y = 0.0
	_portrait_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_portrait_tween.tween_property(_portrait, "position:y", -portrait_bob_height, portrait_bob_seconds * 0.4).set_ease(Tween.EASE_OUT)
	_portrait_tween.tween_property(_portrait, "position:y", 0.0, portrait_bob_seconds * 0.6).set_ease(Tween.EASE_IN_OUT)

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
	%PortraitMount.visible = is_modal and not %DialogueHeader.collapsed
	_layout_dialogue()
	_hint_panel.visible = not is_modal and not _hint_key.is_empty()
	if visible and is_modal:
		if _name_window.visible and not _name_dismissing:
			_name_input.grab_focus()
		elif not _continue.disabled:
			_continue.grab_focus()

func finish() -> void:
	_active = false
	set_practice_done(false, false)
	_close_name_input()
	_warning.stop()
	set_process(false)
	_voice.stop()
	_set_modal(false)

func _exit_tree() -> void:
	if is_modal:
		PauseController.release(PAUSE_REASON)
