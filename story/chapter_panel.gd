extends Control
class_name ChapterPanel

signal talk_requested(character: StoryCharacter)
signal evacuate_requested
var chapter: FirstChapter
@onready var _buttons: Array[Button] = [%Queen, %Planner, %Courier, %Worker]
@onready var _goal: Label = %Goal

func _ready() -> void:
	%Toggle.toggled.connect(func(open: bool): %People.visible = open)
	%Evacuate.pressed.connect(evacuate_requested.emit)
	%Evacuate.pressed.connect(AppSettings.play_click)
	for index in range(_buttons.size()):
		_buttons[index].pressed.connect(_talk.bind(index))
	hide()

func configure(controller: FirstChapter) -> void:
	chapter = controller
	talk_requested.connect(chapter.talk)
	evacuate_requested.connect(chapter.evacuate)
	chapter.presentation_changed.connect(_on_stage_changed)
	show()

func _talk(index: int) -> void:
	var character := _character(index)
	if character != null:
		talk_requested.emit(character)

func _character(index: int) -> StoryCharacter:
	var ids: Array[StringName] = [&"Queen", &"Planner", &"Courier", &"Worker"]
	for character in chapter.rules.characters:
		if character.id == ids[index]:
			return character
	return null

func _on_stage_changed() -> void:
	if chapter.stage == FirstChapter.Stage.EXECUTION:
		%Effects.play(&"execution")

func _process(_delta: float) -> void:
	if chapter == null:
		return
	var blocked := chapter.story.is_modal or Router.has_overlay()
	%Conversations.visible = not blocked and chapter.stage < FirstChapter.Stage.COMPLETE
	%Objectives.visible = not blocked and not chapter.story.hint_bounds().has_area() and chapter.stage < FirstChapter.Stage.COMPLETE
	_goal.text = chapter.status_text()
	%Evacuate.visible = chapter.stage == FirstChapter.Stage.ATTACK
	%Evacuate.disabled = not chapter.can_evacuate()
	for index in range(_buttons.size()):
		var character := _character(index)
		_buttons[index].visible = character != null and (character.id != &"Planner" or chapter.stage < FirstChapter.Stage.EXECUTION)
		_buttons[index].text = character.display_name if character != null else ""
		_buttons[index].disabled = character == null or not chapter.topic_available(character)

func obstacles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for panel: Control in [%Conversations, %Objectives]:
		if panel.is_visible_in_tree():
			result.append(panel.get_global_rect())
	return result

