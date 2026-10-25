extends Node

signal screen_changed(key: StringName)
signal overlay_emptied
signal navigation_started(key: StringName)

var _screen_layer: Node
var _overlay: MenuStack
var _fade: Fade

var _manifest: Manifest
var _current: Screen = null
var _current_key: StringName = &""
var _busy: bool = false

func _ready() -> void:
	# Router must run while paused, overlays are pushed during pause
	process_mode = Node.PROCESS_MODE_ALWAYS

# Boot wiring
func boot(
	manifest: Manifest,
	screen_layer: Node,
	overlay: MenuStack,
	fade: Fade
) -> bool:
	if manifest == null:
		push_error("Router.boot: manifest is null")
		return false
	var errors := manifest.validate()
	if not errors.is_empty():
		for e in errors:
			push_error("Manifest: " + e)
		return false

	_manifest = manifest
	_screen_layer = screen_layer
	_overlay = overlay
	_fade = fade
	_overlay.stack_emptied.connect(_on_stack_emptied)

	goto(manifest.init_key)
	return true

func init() -> void:
	if _manifest != null and not _busy and not is_instance_valid(_current):
		goto(_manifest.init_key)

# Screen navigation

func goto(key: StringName, payload: Variant = null) -> void:
	if _busy or _manifest == null:
		return
	if not _manifest.screens.has(key):
		push_error("Router: screen '%s' is not registered" % key)
		return
	if is_instance_valid(_current) and not _current.can_leave():
		return

	# Validate the replacement before taking the active screen out of play.
	var instance: Node = _manifest.screens[key].instantiate()
	if not instance is Screen:
		instance.free()
		push_error("Router: '%s' root must extend Screen" % key)
		return
	var next_screen: Screen = instance as Screen
	next_screen.payload = payload
	_busy = true

	if is_instance_valid(_current):
		_current.on_blur()
	navigation_started.emit(key)
	# Any overlays are torn down on navigation
	_overlay.clear()
	await _fade.fade_out()
	await _swap_screen(key, next_screen)
	await _fade.fade_in()
	_busy = false
	_current.on_focus()
	screen_changed.emit(key)

func _swap_screen(key: StringName, next_screen: Screen) -> void:
	if is_instance_valid(_current):
		var old: Screen = _current
		_current = null
		old.queue_free()
		await old.tree_exited
	# Payload MUST be set before add_child so _ready() can read it
	_current = next_screen
	_screen_layer.add_child(_current)
	_current_key = key

func is_navigating() -> bool:
	return _busy

# Overlays

func push_overlay(key: StringName, payload: Variant = null) -> MenuBase:
	if _busy:
		return null
	if _manifest == null or not is_instance_valid(_overlay):
		push_error("Router: not booted yet; run the game from the main scene (F5), not the screen on its own")
		return null
	if not _manifest.overlays.has(key):
		push_error("Router: overlay '%s' is not registered" % key)
		return null
	var packed: PackedScene = _manifest.overlays[key]
	var instance: Node = packed.instantiate()
	if not instance is MenuBase:
		instance.free()
		push_error("Router: '%s' root must extend MenuBase" % key)
		return null
	var menu: MenuBase = instance as MenuBase
	menu.payload = payload
	_overlay.push(menu)
	return menu

func pop_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.pop()

func has_overlay() -> bool:
	return is_instance_valid(_overlay) and _overlay.has_menus()

func top_overlay() -> MenuBase:
	return _overlay.top() if is_instance_valid(_overlay) else null

func current_screen_key() -> StringName:
	return _current_key

func current_screen_is_pausable() -> bool:
	return is_instance_valid(_current) and _current.pausable

# Internals

func _on_stack_emptied() -> void:
	overlay_emptied.emit()
