extends Node

signal pause_changed(paused: bool)

var _reasons: Dictionary[StringName, bool] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Router.overlay_emptied.connect(func(): release(&"menu"))
	Router.navigation_started.connect(func(_key: StringName): reset())

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause") or event.is_echo() or Router.is_navigating():
		return
	if not Router.current_screen_is_pausable():
		return
	var top: MenuBase = Router.top_overlay()
	if top != null:
		return
	if _reasons.has(&"result") or _reasons.has(&"voyage_choice"):
		return
	toggle_manual()
	get_viewport().set_input_as_handled()

func toggle_manual() -> void:
	if _reasons.has(&"manual"):
		release(&"manual")
	else:
		acquire(&"manual")

func is_manually_paused() -> bool:
	return _reasons.has(&"manual")

func acquire(reason: StringName) -> void:
	_reasons[reason] = true
	_sync()

func release(reason: StringName) -> void:
	_reasons.erase(reason)
	_sync()

func reset() -> void:
	_reasons.clear()
	_sync()

func _sync() -> void:
	get_tree().paused = not _reasons.is_empty()
	pause_changed.emit(get_tree().paused)

## Leaving the pause menu also resumes a manually paused session.
func resume() -> void:
	release(&"manual")
	Router.pop_overlay()
