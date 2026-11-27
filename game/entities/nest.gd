class_name House
extends Building
signal delivery_requested(resource_id: String, amount: int)
signal stock_order_changed

@export var base_footprint_offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]
@export var capacity: int = 5
@export var is_main_nest := false
## Population limit used only by the main nest.
@export_range(1, 1000) var main_resident_limit := 20
@export var human_scene: PackedScene
@export_range(1.0, 4.0, 0.05) var carrier_speed_multiplier := 1.5
@export_range(1, 100) var carrier_capacity := 6
## Barracks storage in goods. Bases use NestDefaults.base_capacity instead.
@export_range(1, 10000) var storage_capacity := 120
## Whether this store's goods are earmarked for construction before stock orders.
@export var funds_construction := true
## Explicit orders keyed by resource id: {"min": int, "max": int}. Without one, the nest default applies.
var orders: Dictionary = {}
## Positive values request deliveries; negative values send goods to another nest.
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


func show_stock_transfer(cargo: Array[ResourceAmount], incoming_stock: bool) -> void:
	for entry in cargo:
		if entry != null and entry.amount > 0:
			show_stock_change(entry.type, entry.amount if incoming_stock else -entry.amount)

func refresh_appearance() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.modulate = development_tint * (Color.WHITE if is_main_nest else ColonyStyle.color(&"barracks_tint"))

func footprint() -> Array[Vector2i]:
	if not is_main_nest or option is SceneBuildOption:
		return super.footprint()
	var cells: Array[Vector2i] = []
	for offset in base_footprint_offsets:
		cells.append(cell + offset)
	return cells

func display_title() -> String:
	return "ui.storage.main" if is_main_nest else "ui.storage.local"


func resident_limit() -> int:
	return floori((main_resident_limit if is_main_nest else capacity) * terrain_capacity_multiplier + 0.000001)

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
	var maximum := defaults.stock_max_for(defaults.base_capacity if is_main_nest else storage_capacity)
	var minimum := defaults.base_min if is_main_nest else defaults.barracks_min
	return {"min": mini(minimum, maximum), "max": maximum}

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
	stock_order_changed.emit()

## One-time request: the total still owed to this nest for one resource. It shrinks as carriers deliver.
func request(id: String, amount: int) -> void:
	var owed: int = clampi(amount, -WorldInventory.order_limit(), WorldInventory.order_limit())
	if owed == 0:
		requests.erase(id)
	else:
		requests[id] = owed
	delivery_requested.emit(id, owed)

## Called when a carrier delivers cargo to this nest under an order or request.
func fulfil(id: String, amount: int) -> void:
	if int(requests.get(id, 0)) <= 0:
		return
	requests[id] = maxi(0, int(requests[id]) - amount)
	if requests[id] == 0:
		requests.erase(id)

## Export requests count down when a courier physically picks the goods up.
func record_export(id: String, amount: int) -> void:
	if int(requests.get(id, 0)) >= 0:
		return
	requests[id] = mini(0, int(requests[id]) + amount)
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
	if option is NestBuildOption:
		if is_main_nest:
			main_resident_limit = option.resident_capacity
		else:
			capacity = option.resident_capacity
			storage_capacity = option.stock_capacity()
	elif option is SceneBuildOption and option.spawn_count > 0:
		capacity = option.spawn_count
	return true

func _apply_default_appearance(sprite: Sprite2D, art: ArtCatalog) -> void:
	sprite.texture = art.nest

func capture_storage_settings() -> Dictionary:
	return {
		"funds_construction": funds_construction, "storage_capacity": storage_capacity,
		"orders": orders.duplicate(true), "requests": requests.duplicate(),
	}

func restore_storage_settings(state: Dictionary) -> void:
	# Older saves omit storage settings. Keep the values from the loaded scene.
	funds_construction = state.get("funds_construction", funds_construction)
	storage_capacity = state.get("storage_capacity", storage_capacity)
	var saved_orders: Dictionary = state.get("orders", orders)
	var saved_requests: Dictionary = state.get("requests", requests)
	orders = saved_orders.duplicate(true)
	requests = saved_requests.duplicate()
