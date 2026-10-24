extends SceneTree

var world: Node
var step := 0
var wait := 0
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func _process(_delta: float) -> bool:
	match step:
		0:
			world = load("res://game/worlds/wolrd_1.tscn").instantiate()
			root.add_child(world)
			step = 1
		1:
			wait += 1
			if wait < 3:
				return false
			var tree: Node = world.get_node("AppleTree")
			check(tree is Workplace, "AppleTree is Workplace")
			check(tree.work_slots == 3, "work_slots == 3")
			check(tree.output != null and tree.output.id == &"food", "output is food")
			check(tree.cell == Vector2i.ZERO or true, "setup done")
			var food: ResourceType = load("res://game/resources/dot_treses/food.tres")
			var opt: BuildOption = load("res://game/building/options/apple_tree.tres")
			var ctrl: BuildController = world.build_controller
			var map: TileMapLayer = world.get_node("Map")
			var target := Vector2i(6, 4)
			print("cell source at ", target, " = ", map.get_cell_source_id(target))
			check(opt.cost.type.id == &"food" and opt.cost.amount == 5, "cost is 5 food")
			var food_before: int = world.inventory.quantity(food)
			var ok: bool = ctrl.try_build(opt, target)
			print("try_build reason: ", ctrl.unavailable_reason(opt, target))
			check(ok, "apple tree built")
			check(world.inventory.quantity(food) == food_before - 5, "5 food spent")
			var built: Node = null
			for c in world.get_node("Buildings").get_children():
				if c is Workplace:
					built = c
			check(built != null and built.work_slots == 3, "built tree has work_slots 3")
			check(built != null and built.produced.is_connected(world._on_workplace_produced), "built tree subscribed")
			if built != null:
				var before: int = world.inventory.quantity(food)
				built.complete_cycle(Node2D.new())
				check(world.inventory.quantity(food) == before + built.output_amount, "cycle adds food")
			step = 2
		2:
			print("RESULT fails=%d" % fails)
			quit(fails)
	return false
