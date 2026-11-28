class_name CameraSettings
extends Resource

@export var zoom_steps := PackedFloat32Array([0.25, 0.5, 1, 2, 4, 6]):
	set(value):
		if value.is_empty():
			return
		for step in value:
			if not is_finite(step) or step <= 0.0:
				return
		zoom_steps = value
@export var minimum_level := -1
@export var initial_level := 2
@export_range(1.0, 1000.0, 1.0, "or_greater", "suffix:px/s") var pan_speed := 100.0

func maximum_level() -> int:
	return minimum_level + zoom_steps.size() - 1

func clamp_level(value: int) -> int:
	return clampi(value, minimum_level, maximum_level())

func zoom_at(value: int) -> float:
	return zoom_steps[clamp_level(value) - minimum_level]
