extends Node
## Builds a weighted cell graph from a TileMapLayer and answers cell-based route queries.
## The search algorithm is chosen by PATHFINDER_SCRIPT (A* or Dijkstra); callers do not depend on it.

const PATHFINDER_SCRIPT := "res://game/navigation/dijkstra_path_finder.gd" # A*: "res://game/navigation/astar_path_finder.gd"

signal navigation_changed

var _finder: RefCounted = load(PATHFINDER_SCRIPT).new()
var _move_costs: Dictionary = {}


## Rebuild the navigation graph from the supplied TileMapLayer.
## Tiles with a positive `move_cost` are traversable; all other cells are blocked.
func generate(map: TileMapLayer, blocked_cells: Array[Vector2i] = []) -> void:
	_move_costs.clear()

	if not is_instance_valid(map) or map.tile_set == null:
		push_warning("HumanNavigation.generate() requires a TileMapLayer with a TileSet.")
		_finder.build(_move_costs)
		return

	for cell in map.get_used_cells():
		var tile_data := map.get_cell_tile_data(cell)
		if tile_data == null:
			continue

		var cost_value: Variant = tile_data.get_custom_data("move_cost")
		var move_cost := float(cost_value) if cost_value is float or cost_value is int else 0.0
		if move_cost <= 0.0:
			continue
		if blocked_cells.has(cell):
			continue

		_move_costs[cell] = move_cost

	_finder.build(_move_costs)
	navigation_changed.emit()


## Return the least-cost cell path from `from_cell` to `to_cell`, inclusive.
## An empty array means no route exists or an endpoint is not walkable.
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not _move_costs.has(from_cell) or not _move_costs.has(to_cell):
		return []
	return _finder.find_path(from_cell, to_cell)


## Return the total weighted movement cost of the least-cost route.
## Returns INF when no route exists. Each step pays the destination tile's cost.
func get_path_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var path := find_path(from_cell, to_cell)
	if path.is_empty():
		return INF

	var total_cost := 0.0
	for index in range(1, path.size()):
		total_cost += float(_move_costs[path[index]])
	return total_cost
