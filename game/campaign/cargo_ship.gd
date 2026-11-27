class_name CargoShip
extends Building
## Cargo is outside the colony ledger once physically unloaded on board.

@export_range(1, 1000, 1) var capacity_per_resource := 100
var accepting_cargo := false
var manifest: Dictionary[String, int] = {}
var incoming: Dictionary[String, int] = {}
var requirements: Array[ResourceAmount] = []

func need(type: ResourceType) -> int:
	if not accepting_cargo or not requirements.any(func(item: ResourceAmount): return item.type == type):
		return 0
	var id := str(type.id)
	return maxi(0, capacity_per_resource - manifest.get(id, 0) - incoming.get(id, 0))

func accepts(cargo: Array[ResourceAmount]) -> bool:
	if not accepting_cargo:
		return false
	for item in cargo:
		if item == null or item.type == null or item.amount <= 0 or manifest.get(str(item.type.id), 0) + item.amount > capacity_per_resource:
			return false
	return true

func receive(cargo: Array[ResourceAmount], inventory: WorldInventory) -> bool:
	if not accepts(cargo):
		return false
	inventory.begin_update()
	inventory.close_shipment(cargo, false)
	for item in cargo:
		var id := str(item.type.id)
		manifest[id] = manifest.get(id, 0) + item.amount
	inventory.end_update()
	return true

func supplied() -> bool:
	return not requirements.is_empty() and requirements.all(func(item: ResourceAmount): return manifest.get(str(item.type.id), 0) >= item.amount)

