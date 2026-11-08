class_name House
extends Building

const MAIN_RESIDENT_LIMIT := 20
const BARRACKS_TINT := Color("91b7df")
@export var capacity: int = 5
@export var is_main_nest := false
@export var human_scene: PackedScene
@export_range(1.0, 4.0, 0.05) var carrier_speed_multiplier := 1.5
@export_range(1, 100) var carrier_capacity := 6
@export_range(1, 10000) var storage_capacity := 100
@export var auto_dispatch := true
var development_tint := Color.WHITE
var terrain_capacity_multiplier := 1.0

var _residents: Array[Node2D] = []
var residents: Array[Node2D]:
	get:
		_prune()
		return _residents.duplicate()

func _ready() -> void:
	refresh_appearance()

func refresh_appearance() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.modulate = development_tint * (Color.WHITE if is_main_nest else BARRACKS_TINT)

func display_title() -> String:
	return "ui.storage.main" if is_main_nest else "ui.storage.local"


func resident_limit() -> int:
	return floori((MAIN_RESIDENT_LIMIT if is_main_nest else capacity) * terrain_capacity_multiplier + 0.000001)

func has_space() -> bool:
	_prune()
	return _residents.size() < resident_limit()


func add_resident(human: Node2D) -> bool:
	if not is_instance_valid(human) or _residents.has(human) or not has_space():
		return false
	_residents.append(human)
	return true


func remove_resident(human: Node2D) -> void:
	if not is_instance_valid(human):
		_prune()
		return
	_residents.erase(human)


func validate_definition() -> Array[String]:
	var errors: Array[String] = []
	if capacity < 1 or human_scene == null:
		errors.append("Nest needs a positive capacity and an ant scene")
	elif human_scene != null:
		var probe: Node = human_scene.instantiate()
		if not probe is AntAgent:
			errors.append("Nest resident scene must have an AntAgent root")
		probe.free()
	return errors

func _prune() -> void:
	var alive: Array[Node2D] = []
	for resident in _residents:
		if is_instance_valid(resident):
			alive.append(resident)
	_residents = alive

func _on_setup() -> bool:
	if option is SceneBuildOption and option.spawn_count > 0:
		capacity = option.spawn_count
	return true
