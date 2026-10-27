extends Node

## The overlay key that Router should push when pause is requested
@export var pause_menu_key: StringName = &"pause"

var _reasons: Dictionary[StringName, bool] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Router.overlay_emptied.connect(_on_overlay_emptied)
	Router.navigation_started.connect(func(_key: StringName): reset())

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause") or event.is_echo() or Router.is_navigating():
		return

	# The match is over: the result overlay is final, pause must not reopen anything.
	if _reasons.has(&"result"):
		get_viewport().set_input_as_handled()
		return

	# If a menu is open, the pause key acts as "back" (unless the menu is not dismissable)
	if Router.has_overlay():
		var top: MenuBase = Router.top_overlay()
		if top == null or top.dismissable:
			Router.pop_overlay()
		get_viewport().set_input_as_handled()
		return

	# Otherwise only pausable screens react
	if not Router.current_screen_is_pausable():
		return

	if Router.push_overlay(pause_menu_key) != null:
		acquire(&"menu")
	get_viewport().set_input_as_handled()

func acquire(reason: StringName) -> void:
	_reasons[reason] = true
	get_tree().paused = true

func release(reason: StringName) -> void:
	_reasons.erase(reason)
	get_tree().paused = not _reasons.is_empty()

func reset() -> void:
	_reasons.clear()
	get_tree().paused = false

func _on_overlay_emptied() -> void:
	release(&"menu")

## Call this from a "Resume" button inside the pause menu
func resume() -> void:
	Router.pop_overlay()
