extends Node

## The overlay key that Router should push when pause is requested
@export var pause_menu_key: StringName = &"pause"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Router.overlay_emptied.connect(_on_overlay_emptied)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return

	# The match is over: the result overlay is final, pause must not reopen anything.
	if _match_finished():
		get_viewport().set_input_as_handled()
		return

	# If a menu is open, the pause key acts as "back" (unless the menu is not dismissable)
	if Router.has_overlay():
		var top := Router.top_overlay()
		if top == null or top.dismissable:
			Router.pop_overlay()
		get_viewport().set_input_as_handled()
		return

	# Otherwise only pausable screens react
	if not Router.current_screen_is_pausable():
		return

	Router.push_overlay(pause_menu_key)
	get_tree().paused = true
	get_viewport().set_input_as_handled()

func _match_finished() -> bool:
	var match_controller := get_tree().get_first_node_in_group(&"match_controller") as MatchController
	return is_instance_valid(match_controller) and match_controller.is_finished()

func _on_overlay_emptied() -> void:
	if get_tree().paused:
		get_tree().paused = false

## Call this from a "Resume" button inside the pause menu
func resume() -> void:
	Router.pop_overlay()
