extends Node2D
## Standalone regression: local world services populate a nest without global groups.

func _ready() -> void:
	var world: World = load("res://game/worlds/world_1.tscn").instantiate() as World
	world.auto_start = false
	add_child(world)
	var house: House = world.get_node("Home") as House
	var passed: bool = house.residents.size() == 5 and house.has_space() and house.resident_limit() == 20
	var first: Node2D = house.residents[0] if not house.residents.is_empty() else null
	passed = passed and first != null and not house.add_resident(first)
	var fillers: Array[Node2D] = []
	for index in range(15):
		var resident := Node2D.new()
		fillers.append(resident)
		passed = house.add_resident(resident) and passed
	passed = passed and not house.has_space()
	var extra := Node2D.new()
	passed = passed and not house.add_resident(extra)
	extra.free()
	for resident in fillers:
		resident.free()
	print("HOUSE TEST ", "PASS" if passed else "FAIL")
	get_tree().quit(0 if passed else 1)
