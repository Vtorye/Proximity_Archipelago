extends Node

signal screen_changed(key: StringName)
signal overlay_emptied

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
	self.goto(self._manifest.init_key)

# Screen navigation

func goto(key: StringName, payload: Variant = null) -> void:
	if _busy or _manifest == null:
		return
	if not _manifest.screens.has(key):
		push_error("Router: screen '%s' is not registered" % key)
		return
	if is_instance_valid(_current) and not _current.can_leave():
		return

	_busy = true

	# Any overlays are torn down on navigation
	if _overlay.has_menus():
		_overlay.clear()

	if is_instance_valid(_current):
		_current.on_blur()

	await _fade.fade_out()
	await _swap_screen(key, payload)
	await _fade.fade_in()

	_busy = false
	screen_changed.emit(key)

func _swap_screen(key: StringName, payload: Variant) -> void:
	if is_instance_valid(_current):
		_current.queue_free()
		await _current.tree_exited

	var packed := _manifest.screens[key] #load(_registry[key]) as PackedScene
	if packed == null:
		push_error("Router: failed to load '%s'" % _manifest.screens[key])		
		_busy = false
		return

	_current = packed.instantiate() as Screen
	if _current == null:
		push_error("Router: '%s' root must extend Screen" % key)
		_busy = false
		return

	# Payload MUST be set before add_child so _ready() can read it
	_current.payload = payload

	_screen_layer.add_child(_current)
	_current_key = key
	_current.on_focus()

# Overlays

func push_overlay(key: StringName, payload: Variant = null) -> MenuBase:
	if not _manifest.overlays.has(key):
		push_error("Router: overlay '%s' is not registered" % key)
		return null
	var packed :=  _manifest.overlays[key]
	var menu := packed.instantiate() as MenuBase
	if menu == null:
		push_error("Router: '%s' root must extend MenuBase" % key)
		return null
	menu.payload = payload
	_overlay.push(menu)
	return menu

func pop_overlay() -> void:
	_overlay.pop()

func has_overlay() -> bool:
	return _overlay.has_menus()

func current_screen_key() -> StringName:
	return _current_key

func current_screen_is_pausable() -> bool:
	return is_instance_valid(_current) and _current.pausable

# Internals

func _on_stack_emptied() -> void:
	overlay_emptied.emit()
