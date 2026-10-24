extends Node2D
class_name World

@export var starting_resources: Array[ResourceAmount] = []
@export var build_options: Array[BuildOption] = []

var inventory: WorldInventory
var build_controller: BuildController


func _ready() -> void:
	var map := $Map as TileMapLayer
	inventory = WorldInventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
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
	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	add_child(build_controller)
	build_controller.configure(map, buildings, inventory, build_options)
	# All setup() calls must finish before navigation is generated,
	# otherwise units spawned by houses would appear before the grid exists.
	for child in get_children():
		if child is Building:
			var building := child as Building
			var origin := map.local_to_map(map.to_local(building.global_position))
			building.setup(inventory, origin, null)
			build_controller.reserve_existing(building)
		elif child is Workplace or child is Canteen:
			build_controller.reserve_existing(child)
	HumanNavigation.generate(map)


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
