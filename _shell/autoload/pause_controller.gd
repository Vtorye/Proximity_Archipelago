extends Node

## The overlay key that Router should push when pause is requested
@export var pause_menu_key: StringName = &"pause"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Router.overlay_emptied.connect(_on_overlay_emptied)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return

	# If a menu is open, the pause key acts as "back"
	if Router.has_overlay():
		Router.pop_overlay()
		get_viewport().set_input_as_handled()
		return

	# Otherwise only pausable screens react
	if not Router.current_screen_is_pausable():
		return

	Router.push_overlay(pause_menu_key)
	get_tree().paused = true
	get_viewport().set_input_as_handled()

func _on_overlay_emptied() -> void:
	if get_tree().paused:
		get_tree().paused = false

## Call this from a "Resume" button inside the pause menu
func resume() -> void:
	Router.pop_overlay()
