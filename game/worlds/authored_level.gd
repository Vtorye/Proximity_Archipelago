class_name AuthoredLevel
extends Resource
## Bundled maps use resources so their dependencies are included in exported builds.
@export var title: String
@export_multiline var description: String
@export var layout: Dictionary

func data() -> Dictionary:
	var result: Dictionary = layout.duplicate(true)
	result["title"] = title
	result["description"] = description
	return result
