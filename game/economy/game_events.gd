class_name GameEvents
extends RefCounted
## The editor and runtime share this closed vocabulary. Subjects are catalog IDs.
enum Kind { BUILDING_BUILT, BUILDING_DEMOLISHED, RESOURCE_PRODUCED, TASK_COMPLETED, LEVEL_ADVANCED }

static func key(event: int, subject: StringName) -> String:
	return "%d:%s" % [event, subject]
