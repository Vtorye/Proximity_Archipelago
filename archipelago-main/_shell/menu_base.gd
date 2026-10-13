class_name MenuBase
extends Control

## Emitted when Back is pressed. The MenuStack listens and pops
signal close_requested(menu: MenuBase)

## Optional data handed in by Router.push_overlay()
var payload: Variant = null

## The control that should receive focus when this menu is shown
## Set in the Inspector. If null, the first focusable control is used
@export var default_focus: Control

func grab_focus_default() -> void:
	if is_instance_valid(default_focus):
		default_focus.grab_focus()
		return
	# Fallback: first focusable Control in tree order
	for child in find_children("*", "Control", true, false):
		var c := child as Control
		if c and c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree():
			c.grab_focus()
			return

func _unhandled_input(event: InputEvent) -> void:
	# Hidden menus must not react to input
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close_requested.emit(self)
		get_viewport().set_input_as_handled()
