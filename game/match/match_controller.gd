class_name MatchController
extends Node
## Owns the match rules: countdown, victory and defeat. Must be a direct child of World.
##
## Victory: every type in tracked_types has at least target_amount in the world inventory.
## Defeat: the timer reaches 0 without victory.
## Only one result is ever produced per match.

## Group used by HUD and PauseController to find the active match.
const GROUP := &"match_controller"

enum Result { WIN, LOSS }
enum Reason { TARGET_REACHED, TIME_UP }

## Emitted once per whole second left (and once at start).
signal time_changed(seconds_left: int)
signal match_won(reason: Reason)
signal match_lost(reason: Reason)

@export var match_duration: float = 300.0
@export var target_amount: int = 100
@export var tracked_types: Array[ResourceType] = []

var time_remaining: float = 0.0
var _finished := false
var _started := false
var _last_seconds := -1
var _inventory: WorldInventory


func _ready() -> void:
	set_process(false)
	add_to_group(GROUP)
	# Parent World creates its inventory in its own _ready(), which runs after this one.
	_start.call_deferred()


func _exit_tree() -> void:
	_started = false
	set_process(false)
	remove_from_group(GROUP)
	if is_instance_valid(_inventory) and _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.disconnect(_on_inventory_changed)
	_inventory = null


func is_finished() -> bool:
	return _finished


func _start() -> void:
	if not is_inside_tree():
		return
	var world := get_parent() as World
	if world == null or world.inventory == null:
		push_error("MatchController must be a direct child of World with an inventory")
		return
	_inventory = world.inventory
	_inventory.changed.connect(_on_inventory_changed)
	time_remaining = match_duration
	_started = true
	_last_seconds = ceili(time_remaining)
	time_changed.emit(_last_seconds)
	set_process(true)


func _process(delta: float) -> void:
	if _finished or not _started:
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	var seconds := ceili(time_remaining)
	if seconds != _last_seconds:
		_last_seconds = seconds
		time_changed.emit(seconds)
	if time_remaining <= 0.0:
		# Victory wins over timeout if both hold in the same frame.
		if _targets_met():
			_finish(Result.WIN, Reason.TARGET_REACHED)
		else:
			_finish(Result.LOSS, Reason.TIME_UP)


func _on_inventory_changed() -> void:
	if _finished or not _started:
		return
	if _targets_met():
		# Deferred: the change may come from inside BuildController.try_build() or demolish_at(),
		# where _committing is still true. The result is applied at the end of the frame.
		_finish.call_deferred(Result.WIN, Reason.TARGET_REACHED)


func _targets_met() -> bool:
	if _inventory == null or tracked_types.is_empty():
		return false
	for type in tracked_types:
		if _inventory.quantity(type) < target_amount:
			return false
	return true


func _finish(result: Result, reason: Reason) -> void:
	if _finished:
		return
	_finished = true
	_started = false
	set_process(false)
	var resources := {}
	if _inventory != null:
		for type in _inventory.registered_types():
			resources[type.display_name] = _inventory.quantity(type)
	var payload := {
		"result": "WIN" if result == Result.WIN else "LOSS",
		"reason": Reason.keys()[reason],
		"resources": resources,
		"time_left": time_remaining,
	}
	if result == Result.WIN:
		match_won.emit(reason)
	else:
		match_lost.emit(reason)
	get_tree().paused = true
	Router.push_overlay(&"match_result", payload)
