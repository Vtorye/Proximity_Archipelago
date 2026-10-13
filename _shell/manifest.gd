extends Resource
class_name Manifest

@export
var init_key: StringName

@export
var screens: Dictionary[StringName, PackedScene]

@export
var overlays: Dictionary[StringName, PackedScene]

func validate() -> Array[String]:
	var errs: Array[String] = []
	if init_key == &"":
		errs.append("init_key is empty")
	elif not screens.has(init_key):
		errs.append("init_key '%s' not present in screens" % init_key)
	for key in screens:
		if key == &"":
			errs.append("screens contains empty key")
		elif screens[key] == null:
			errs.append("screens['%s'] is null" % key)
	for key in overlays:
		if key == &"":
			errs.append("overlays contains empty key")
		elif overlays[key] == null:
			errs.append("overlays['%s'] is null" % key)
	return errs
