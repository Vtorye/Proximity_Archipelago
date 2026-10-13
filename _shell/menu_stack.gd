class_name MenuStack
extends Control

signal pushed(menu: MenuBase)
signal popped(menu: MenuBase)
signal stack_emptied

var _stack: Array[MenuBase] = []

func push(menu: MenuBase) -> void:
	if not is_instance_valid(menu):
		return
	if not _stack.is_empty():
		_stack.back().hide()
	menu.close_requested.connect(_on_close_requested)
	add_child(menu)
	_stack.append(menu)
	menu.grab_focus_default()
	pushed.emit(menu)

func pop() -> void:
	if _stack.is_empty():
		return
	var top: MenuBase = _stack.pop_back()
	if is_instance_valid(top):
		top.queue_free()
	popped.emit(top)
	if not _stack.is_empty():
		_stack.back().show()
		_stack.back().grab_focus_default()
	else:
		stack_emptied.emit()

func clear() -> void:
	if _stack.is_empty():
		return
	for menu in _stack:
		if is_instance_valid(menu):
			menu.queue_free()
	_stack.clear()
	stack_emptied.emit()

func has_menus() -> bool:
	return not _stack.is_empty()

func count() -> int:
	return _stack.size()

## Only the topmost meny may pop itself
## This guards against a hidden menu emitting close_requested by accident
func _on_close_requested(menu: MenuBase) -> void:
	if _stack.is_empty() or _stack.back() != menu:
		return
	pop()
