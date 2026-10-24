extends Node2D
class_name World

@export var starting_resources: Array[ResourceAmount] = []
@export var build_options: Array[BuildOption] = []

var inventory: WorldInventory
var build_controller: BuildController
var route_service: RouteService


func _ready() -> void:
	var map := $Map as TileMapLayer
	inventory = WorldInventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	route_service = RouteService.new()
	route_service.name = "RouteService"
	add_child(route_service)
	route_service.setup(map)
	route_service.add_to_group(&"route_service")
	if not inventory.configure(starting_resources):
		return
	var units := Node2D.new()
	units.name = "Units"
	add_child(units)
	units.add_to_group(&"units_root")
	# Buildings added later are drawn above units by tree order; keep units on top.
	units.z_index = 1
	var buildings := Node2D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	# Workplaces built later through BuildController enter the tree under this node.
	buildings.child_entered_tree.connect(_subscribe_workplace)
	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	build_controller.route_service = route_service
	add_child(build_controller)
	build_controller.configure(map, buildings, inventory, build_options)
	# All setup() calls must finish before navigation is generated,
	# otherwise units spawned by houses would appear before the grid exists.
	for child in get_children():
		if child is Building:
			var building := child as Building
			var origin := map.local_to_map(map.to_local(building.global_position))
			building.setup(origin, null)
			_subscribe_workplace(building)
			build_controller.reserve_existing(building)
	route_service.rebuild(build_controller.blocked_cells())


## Connects a workplace's output to the world inventory. Safe to call more than once.
func _subscribe_workplace(node: Node) -> void:
	if not node is Workplace:
		return
	var workplace := node as Workplace
	if not workplace.produced.is_connected(_on_workplace_produced):
		workplace.produced.connect(_on_workplace_produced)


func _on_workplace_produced(type: ResourceType, amount: int) -> void:
	if not inventory.add(type, amount):
		push_warning("World could not store %d of %s" % [amount, type.id])


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if not is_instance_valid(build_controller) or Router.has_overlay():
		return
	var map := $Map as TileMapLayer
	var local_position: Vector2 = map.get_global_transform_with_canvas().affine_inverse() * event.position
	var cell := map.local_to_map(local_position)
	if map.get_cell_source_id(cell) == -1:
		return
	Router.push_overlay(&"build", {"controller": build_controller, "cell": cell})
	get_viewport().set_input_as_handled()
