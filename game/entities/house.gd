class_name House
extends Building

const MAIN_RESIDENT_LIMIT := 20
const BARRACKS_TINT := Color("91b7df")
@export var capacity: int = 5
@export var is_main_nest := false
@export var human_scene: PackedScene
@export_range(1.0, 4.0, 0.05) var carrier_speed_multiplier := 1.5
@export_range(1, 100) var carrier_capacity := 6
## Barracks storage in goods. Bases use NestDefaults.base_capacity instead.
@export_range(1, 10000) var storage_capacity := 120
## Whether this store's goods are earmarked for construction before stock orders.
@export var funds_construction := true
## Explicit orders keyed by resource id: {"min": int, "max": int}. Without one, the nest default applies.
var orders: Dictionary = {}
## One-time requests still owed to this nest, keyed by resource id.
var requests: Dictionary = {}
## Units en route to this nest under an order or request, keyed by resource id.
var incoming: Dictionary = {}
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


## Order in effect for one resource: explicit, else the nest default from nest_defaults.tres.
func order_of(id: String) -> Dictionary:
	if orders.has(id):
		return orders[id]
	var defaults: NestDefaults = NestDefaults.load_defaults()
	if is_main_nest:
		return {"min": defaults.base_min, "max": defaults.base_max}
	return {"min": defaults.barracks_min, "max": defaults.barracks_max}

## Keeps min <= max. Editing max below min lowers min, and editing min above max raises max.
func set_order(id: String, field: String, value: int) -> void:
	var order: Dictionary = order_of(id).duplicate()
	order[field] = clampi(value, 0, WorldInventory.order_limit())
	if order.min > order.max:
		if field == "min":
			order.max = order.min
		else:
			order.min = order.max
	orders[id] = order

## One-time request: the total still owed to this nest for one resource. It shrinks as carriers deliver.
func request(id: String, amount: int) -> void:
	var owed: int = clampi(amount, 0, WorldInventory.order_limit())
	if owed <= 0:
		requests.erase(id)
	else:
		requests[id] = owed

## Called when a carrier delivers cargo to this nest under an order or request.
func fulfil(id: String, amount: int) -> void:
	if not requests.has(id):
		return
	requests[id] = maxi(0, int(requests[id]) - amount)
	if requests[id] == 0:
		requests.erase(id)

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
