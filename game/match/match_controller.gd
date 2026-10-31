class_name MatchController
extends Node
## Owns the match rules: countdown, victory and defeat. Receives its inventory explicitly before start.
##
## Victory: every type in tracked_types has at least target_amount in the world inventory.
## Defeat: the timer reaches 0 without victory.
## Only one result is ever produced per match.

enum Result { WIN, LOSS }
enum Reason { TARGET_REACHED, TIME_UP }

## Emitted once per whole second left (and once at start).
signal time_changed(seconds_left: int)
signal match_won(reason: Reason)
signal match_lost(reason: Reason)
signal completed(summary: MatchSummary)

@export var match_duration: float = 180.0
@export var target_amount: int = 100
@export var tracked_types: Array[ResourceType] = []

var task_mode := false
var time_remaining: float = 0.0
var _finished := false
var _started := false
var _last_seconds := -1
var _inventory: WorldInventory


func _ready() -> void:
	set_process(false)
	# Parent World creates its inventory in its own _ready(), which runs after this one.
	# It calls start() explicitly after the complete world has been configured.


func _exit_tree() -> void:
	_started = false
	set_process(false)
	if is_instance_valid(_inventory) and _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.disconnect(_on_inventory_changed)
	_inventory = null


func is_finished() -> bool:
	return _finished


func start(stock: WorldInventory) -> bool:
	if _started or _finished or stock == null or tracked_types.is_empty():
		return false
	if match_duration <= 0.0 or target_amount <= 0:
		return false
	for type in tracked_types:
		if type == null or not stock.is_registered(type):
			return false
	_inventory = stock
	_inventory.changed.connect(_on_inventory_changed)
	time_remaining = match_duration
	_started = true
	_last_seconds = ceili(time_remaining)
	time_changed.emit(_last_seconds)
	set_process(true)
	_evaluate.call_deferred()
	return true


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
	# Deferred: the change may come from inside BuildController.try_build() or demolish_at(),
	# where a command may still be running. Recheck after the complete operation.
	_evaluate.call_deferred()

func _evaluate() -> void:
	# Recheck committed stock instead of latching an intermediate inventory value.
	if _started and not _finished and _targets_met():
		_finish(Result.WIN, Reason.TARGET_REACHED)

func stop() -> void:
	_started = false
	set_process(false)

func _targets_met() -> bool:
	if task_mode or _inventory == null or tracked_types.is_empty():
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
	var cause: StringName = &"target_reached" if reason == Reason.TARGET_REACHED else &"time_up"
	var summary: MatchSummary = MatchSummary.capture(result == Result.WIN, cause, time_remaining, _inventory)
	if result == Result.WIN:
		match_won.emit(reason)
	else:
		match_lost.emit(reason)
	completed.emit(summary)

func add_time(seconds: float) -> void:
	if _finished or not _started or seconds < 0 or not is_finite(seconds): return
	time_remaining += seconds
	_last_seconds = ceili(time_remaining)
	time_changed.emit(_last_seconds)

func complete_objective() -> void:
	if _started and not _finished: _finish(Result.WIN, Reason.TARGET_REACHED)

func is_active() -> bool:
	return _started and not _finished
