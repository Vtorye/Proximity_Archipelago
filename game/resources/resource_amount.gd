class_name ResourceAmount
extends Resource

@export var type: ResourceType
@export_range(0, 1000000) var amount: int = 1

static func pack(items: Array) -> Array:
	var result: Array = []
	for item: ResourceAmount in items: result.append([str(item.type.id), item.amount])
	return result

static func unpack(items: Array, resolve_type: Callable) -> Array[ResourceAmount]:
	var result: Array[ResourceAmount] = []
	for row in items:
		var type: ResourceType = resolve_type.call(StringName(row[0]))
		if type == null: continue
		var item := ResourceAmount.new()
		item.type = type
		item.amount = int(row[1])
		result.append(item)
	return result
