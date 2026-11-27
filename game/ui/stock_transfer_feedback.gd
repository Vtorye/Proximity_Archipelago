extends Marker2D

const StockTransfer := preload("res://game/ui/stock_transfer.gd")

@export var transfer_scene: PackedScene
@export_range(0.0, 100.0, 1.0) var spacing := 22.0


func show_change(resource: ResourceType, amount: int) -> void:
	if resource == null or amount == 0 or transfer_scene == null or not is_inside_tree():
		return
	var offset := 0.0
	for child in get_children():
		var active := child as StockTransfer
		if active != null:
			offset = minf(offset, active.position.y - spacing)
	var indicator := transfer_scene.instantiate() as StockTransfer
	indicator.position.y = offset
	add_child(indicator)
	indicator.play(resource, amount)
