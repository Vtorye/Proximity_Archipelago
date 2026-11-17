extends RefCounted
## Optional wall-clock counters for the navigation stress scene.
static var enabled := false
static var _names: Array[StringName] = []
static var _starts: Array[int] = []
static var _children: Array[int] = []
static var _exclusive: Dictionary[StringName, int] = {}
static var _calls: Dictionary[StringName, int] = {}

static func begin(section: StringName) -> void:
	_names.append(section)
	_children.append(0)
	_starts.append(Time.get_ticks_usec())

static func end() -> void:
	var duration: int = Time.get_ticks_usec() - _starts.pop_back()
	var section: StringName = _names.pop_back()
	var child_time: int = _children.pop_back()
	_exclusive[section] = _exclusive.get(section, 0) + duration - child_time
	_calls[section] = _calls.get(section, 0) + 1
	if not _children.is_empty():
		_children[_children.size() - 1] += duration

static func sample() -> Dictionary:
	var result := {"exclusive_us": _exclusive, "calls": _calls}
	_exclusive = {}
	_calls = {}
	return result
