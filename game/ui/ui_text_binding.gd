extends Node
## Applies the selected typography to one branch of the interface.
@export var target: Control

func _ready() -> void:
	AppSettings.text_size_changed.connect(_apply_size)
	_apply_size()

func _apply_size() -> void:
	var selected_theme := ColonyStyle.theme_for_text_size(AppSettings.text_size)
	if target.theme != selected_theme:
		target.theme = selected_theme
