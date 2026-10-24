extends Node2D

func _ready() -> void:
	# Нужен узел, в который будут падать юниты
	var units := Node2D.new()
	units.add_to_group("units_root")
	add_child(units)

	var house_scene: PackedScene = load("res://game/entities/house.tscn")	
	var house: House = house_scene.instantiate()
	add_child(house)

	# Ручной вызов setup, как это будет делать BuildController
	house.setup(Vector2i.ZERO, null)

	print("жильцов: ", house.residents.size(), " (ожидаем 5)")
	print("has_space: ", house.has_space(), " (ожидаем false)")

	# Повторное добавление уже живущего юнита
	var first: Node2D = house.residents[0]
	print("повтор add_resident: ", house.add_resident(first), " (ожидаем false)")

	# Дополнительный юнит сверх вместимости
	var extra := Node2D.new()
	print("add_resident сверх лимита: ", house.add_resident(extra), " (ожидаем false)")
