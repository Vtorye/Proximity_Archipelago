class_name DebugProbe
extends Node
## Debug-only observer. Changes no game state.
## Logs unit spawns, deaths, status transitions, building setup/demolish/build and periodic summaries.
## Output goes to the Godot console and to user://debug_probe.log.

const HUMAN_SCRIPT := preload("res://game/entities/human.gd")
const LOG_PATH := "user://debug_probe.log"

@export var enabled: bool = true
@export var summary_interval: float = 5.0

var _file: FileAccess
var _world: Node
var _units: Node
var _buildings: Node
var _controller: BuildController
var _last_status: Dictionary = {}
var _summary_timer := 0.0


func _ready() -> void:
	if not enabled:
		return
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_warning("DebugProbe: cannot open %s (error %d)" % [LOG_PATH, FileAccess.get_open_error()])
	_log("probe", "started, file: %s" % ProjectSettings.globalize_path(LOG_PATH))
	# Parent World finishes its _ready (inventory, controller, navigation) during this wait.
	await get_tree().process_frame
	_world = get_parent()
	_units = get_tree().get_first_node_in_group("units_root")
	if _units == null:
		_log("WARN", "no node in group units_root; unit logging disabled")
	else:
		_units.child_entered_tree.connect(_on_unit_entered)
		for unit in _units.get_children():
			_on_unit_entered(unit)
	_buildings = _world.get_node_or_null("Buildings")
	if _buildings == null:
		_log("WARN", "no Buildings node under %s; building logging disabled" % _world.name)
	else:
		_buildings.child_entered_tree.connect(_on_building_entered)
	_controller = _world.get_node_or_null("BuildController") as BuildController
	if _controller == null:
		_log("WARN", "no BuildController under %s; build logging disabled" % _world.name)
	else:
		_controller.built.connect(_on_built)
	for child in _world.get_children():
		if child is Building:
			_log("building", "present at start: %s cell=%s option=%s" % [child.name, (child as Building).cell, _option_id(child)])


func _exit_tree() -> void:
	if _file != null:
		_file.flush()
		_file = null


func _process(delta: float) -> void:
	if not enabled or _world == null:
		return
	_check_statuses()
	_summary_timer += delta
	if _summary_timer >= summary_interval:
		_summary_timer = 0.0
		_print_summary()


# --- Units -----------------------------------------------------------------

func _on_unit_entered(node: Node) -> void:
	if not _is_human(node):
		return
	node.died.connect(_on_unit_died)
	var home = node.get("home")
	_log("unit", "spawned %s home=%s home_valid=%s" % [node.name, _home_name(home), is_instance_valid(home)])


func _on_unit_died(human: Node2D) -> void:
	var home = human.get("home")
	var last := "unknown"
	if _last_status.has(human.get_instance_id()):
		last = _status_name(_last_status[human.get_instance_id()])
	var residents := "-"
	if is_instance_valid(home) and home is House:
		residents = "%d/%d" % [(home as House).residents.size(), (home as House).capacity]
	_log("DEATH", "%s last_status=%s pos=%s home=%s home_residents=%s" % [
		human.name, last, human.global_position, _home_name(home), residents])


func _check_statuses() -> void:
	var alive := {}
	for human in get_tree().get_nodes_in_group("humans"):
		if not is_instance_valid(human) or not _is_human(human):
			continue
		var id := human.get_instance_id()
		alive[id] = true
		var current: int = human.get("status")
		if _last_status.has(id):
			var previous: int = _last_status[id]
			if previous != current:
				_log("status", "%s %s -> %s" % [human.name, _status_name(previous), _status_name(current)])
		else:
			_log("status", "%s first seen: %s" % [human.name, _status_name(current)])
		_last_status[id] = current
	for id in _last_status.keys():
		if not alive.has(id):
			_last_status.erase(id)


# --- Buildings -------------------------------------------------------------

func _on_building_entered(node: Node) -> void:
	if not node is Building:
		return
	node.demolished.connect(_on_building_demolished)
	# setup() runs synchronously right after add_child, so a deferred log sees its result.
	_log_building_setup.call_deferred(node)


func _log_building_setup(building: Building) -> void:
	if not is_instance_valid(building):
		return
	var extra := ""
	if building is House:
		var house := building as House
		extra = " residents=%d/%d" % [house.residents.size(), house.capacity]
	_log("setup", "%s cell=%s option=%s%s" % [building.name, building.cell, _option_id(building), extra])
	if building is House and _units != null:
		var count := 0
		for unit in _units.get_children():
			if _is_human(unit) and unit.get("home") == building:
				count += 1
		_log("setup", "%s units in Units with this home: %d" % [building.name, count])


func _on_building_demolished(building: Building) -> void:
	var remaining := _units.get_child_count() if _units != null else -1
	_log("demolish", "%s cell=%s option=%s units_left_in_Units=%d" % [
		building.name, building.cell, _option_id(building), remaining])


func _on_built(option: BuildOption, cell: Vector2i) -> void:
	var units := _units.get_child_count() if _units != null else -1
	_log("built", "option=%s cell=%s stock=[%s] units_in_Units=%d" % [
		option.id if option != null else "null", cell, _stock_string(), units])


# --- Summary ---------------------------------------------------------------

func _print_summary() -> void:
	_log("summary", "stock=[%s] units=%d" % [_stock_string(), _units.get_child_count() if _units != null else -1])
	for house in get_tree().get_nodes_in_group("houses"):
		if house is House:
			var h := house as House
			_log("summary", "house %s residents=%d/%d has_space=%s" % [h.name, h.residents.size(), h.capacity, h.has_space()])
	for human in get_tree().get_nodes_in_group("humans"):
		if not _is_human(human) or not is_instance_valid(human):
			continue
		var status: int = human.get("status")
		var destination = human.get("_destination")
		var dest_name := "none"
		if is_instance_valid(destination):
			dest_name = destination.name
		var path = human.get("_path")
		var path_size: int = path.size() if path != null else 0
		var home = human.get("home")
		_log("summary", "unit %s status=%s dest=%s path=%d home_valid=%s" % [
			human.name, _status_name(status), dest_name, path_size, is_instance_valid(home)])
		if status == HUMAN_SCRIPT.Status.WALKING and path_size == 0 and dest_name == "none":
			_log("WARN", "%s is WALKING without destination or path" % human.name)
		if not is_instance_valid(home):
			_log("WARN", "%s has no valid home" % human.name)


# --- Helpers ---------------------------------------------------------------

func _is_human(node: Node) -> bool:
	return node.get_script() == HUMAN_SCRIPT


func _status_name(status: int) -> String:
	var names: Array = HUMAN_SCRIPT.Status.keys()
	return String(names[status]) if status >= 0 and status < names.size() else "UNKNOWN(%d)" % status


func _home_name(home) -> String:
	return String(home.name) if is_instance_valid(home) else "none"


func _option_id(building: Node) -> String:
	if building is Building and (building as Building).option != null:
		return String((building as Building).option.id)
	return "none"


func _stock_string() -> String:
	if _controller == null or _controller.inventory == null:
		return "no inventory"
	var parts: PackedStringArray = []
	for type in _controller.inventory.registered_types():
		parts.append("%s=%d" % [type.id, _controller.inventory.quantity(type)])
	return ", ".join(parts)


func _log(category: String, message: String) -> void:
	var line := "[frame %d][%.2fs][%s] %s" % [
		Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0, category, message]
	print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()
