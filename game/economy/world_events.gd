class_name WorldEvents
extends RefCounted
## A world-local stream of typed facts. Consumers do not depend on one another.
signal occurred(event: GameEvents.Kind, subject: StringName, amount: int)
var _counts: Dictionary[String, int] = {}
func publish(event: GameEvents.Kind, subject: StringName = &"", amount: int = 1) -> void:
	assert(event >= 0 and event < GameEvents.Kind.size() and amount >= 0)
	var id: String = GameEvents.key(event, subject)
	_counts[id] = _counts.get(id, 0) + 1
	if subject != &"":
		var all: String = GameEvents.key(event, &"")
		_counts[all] = _counts.get(all, 0) + 1
	occurred.emit(event, subject, amount)
func count(event: GameEvents.Kind, subject: StringName) -> int:
	return _counts.get(GameEvents.key(event, subject), 0)
