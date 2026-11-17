extends MenuBase
class_name StoryOverlay

signal episode_finished

@export var character_portraits: Dictionary[StringName, Texture2D] = {}
var episode: StoryEpisode
var _dialogue_line: DialogueLine
var _waiting_for_action := false
var _awaiting_action := false
var _completed_actions: Dictionary[StringName, bool] = {}
var _pause_reason: StringName = &"story_overlay"
var _dialogue_manager: Node
var awaiting_action: bool:
	get:
		return _awaiting_action or (_dialogue_line != null and _dialogue_line.has_tag("action"))

@onready var _speaker: Label = %Speaker
@onready var _dialogue: Label = %Dialogue
@onready var _portrait: TextureRect = %Portrait
@onready var _continue: Button = %Continue
@onready var _skip_to_action: Button = %SkipToAction
@onready var _skip_episode: Button = %SkipEpisode

func _ready() -> void:
	if not payload is StoryEpisode:
		push_error("StoryOverlay requires a StoryEpisode payload")
		close_requested.emit(self)
		return
	episode = payload as StoryEpisode
	_dialogue_manager = Engine.get_singleton("DialogueManager")
	_continue.pressed.connect(_on_continue)
	_skip_to_action.pressed.connect(_skip_to_next_action)
	_skip_episode.pressed.connect(_finish_episode)
	if episode.pause_simulation:
		PauseController.acquire(_pause_reason)
	_request_line("")

func _exit_tree() -> void:
	if PauseController != null:
		PauseController.release(_pause_reason)

func _request_line(next_id: String, stop_at_action := false) -> void:
	while is_inside_tree():
		_dialogue_line = await _dialogue_manager.get_next_dialogue_line(episode.dialogue, next_id, [self])
		if not is_inside_tree():
			return
		if _dialogue_line == null:
			_finish_episode()
			return
		if not stop_at_action or _dialogue_line.has_tag("action"):
			break
		next_id = _dialogue_line.next_id
	_speaker.text = tr("ui.story.queen") if _dialogue_line.character == "Queen" else tr("ui.story.protagonist")
	_dialogue.text = tr(_dialogue_line.text)
	var portrait_path := _dialogue_line.get_tag_value("portrait")
	_portrait.texture = load(portrait_path) as Texture2D if not portrait_path.is_empty() else character_portraits.get(StringName(_dialogue_line.character))
	_waiting_for_action = _awaiting_action
	_continue.disabled = _waiting_for_action
	_continue.text = tr("ui.story.waiting") if _waiting_for_action else tr("ui.story.continue")
	_skip_to_action.disabled = _waiting_for_action or _dialogue_line.has_tag("action")

func _on_continue() -> void:
	if _waiting_for_action:
		return
	_request_line(_dialogue_line.next_id)

func _skip_to_next_action() -> void:
	if _waiting_for_action or _dialogue_line == null:
		return
	_request_line(_dialogue_line.next_id, true)

## Game systems call this when their action signal matches the current checkpoint.
func wait_for_action(action_id: String) -> void:
	var requested_action := StringName(action_id)
	if _completed_actions.has(requested_action):
		_completed_actions.erase(requested_action)
		return
	_awaiting_action = true
	_waiting_for_action = true
	_continue.disabled = true
	_continue.text = tr("ui.story.waiting")
	while is_inside_tree() and _awaiting_action:
		var reached_id: StringName = await action_occurred
		if reached_id == requested_action:
			_awaiting_action = false
	_waiting_for_action = false
	_continue.disabled = false
	_continue.text = tr("ui.story.continue")

signal action_occurred(action_id: StringName)

func complete_action(action_id: StringName) -> void:
	if _awaiting_action:
		action_occurred.emit(action_id)
	else:
		_completed_actions[action_id] = true

func _finish_episode() -> void:
	episode_finished.emit()
	close_requested.emit(self)
