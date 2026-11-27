class_name ConversationsMenu
extends Control

signal character_selected(character: StoryCharacter)
@export var dock_margin := Vector2(8, 4)
var characters: Array[StoryCharacter] = []
var available: Callable
var _buttons: Array[Button] = []
@onready var _panel: PanelContainer = %Panel
@onready var header: WindowHeader = %WindowHeader

func configure(definitions: Array[StoryCharacter], can_talk: Callable) -> void:
	characters = definitions
	available = can_talk
	for character in characters:
		if character.id == &"Protagonist":
			continue
		var button: Button = preload("res://game/ui/palette_entry.tscn").instantiate()
		button.text = character.display_name
		button.pressed.connect(AppSettings.play_click)
		button.pressed.connect(character_selected.emit.bind(character))
		%People.add_child(button)
		_buttons.append(button)
		button.set_meta(&"character", character)

func dock_above(bottom_height: float) -> void:
	_panel.reset_size()
	_panel.size.x = get_viewport_rect().size.x - dock_margin.x * 2.0
	header.place(Vector2(dock_margin.x, get_viewport_rect().size.y - bottom_height - _panel.size.y - dock_margin.y))

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	for button in _buttons:
		button.disabled = available.is_valid() and not available.call(button.get_meta(&"character"))

func panel_bounds() -> Rect2:
	return _panel.get_global_rect()
