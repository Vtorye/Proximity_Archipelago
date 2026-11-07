class_name WaveSpawner
extends RefCounted
## Shore spawns use painted terrain connectivity, so enclosing a colony cannot spawn enemies inside its walls.
var director: CombatDirector
var number := 0
var remaining := 0.0

func tick(delta: float) -> void:
	remaining -= delta
	if remaining > 0: return
	var cells: Array[Vector2i] = spawn_cells()
	if cells.is_empty():
		remaining = 1.0
		return
	number += 1
	var count: int = mini(director.rules.maximum_spiders - director.spiders.size(), director.rules.initial_spiders + (number - 1) * director.rules.spiders_per_wave)
	for index in range(count): director.spawn_spider(cells.pick_random())
	remaining = director.rules.wave_interval_seconds
	director.changed.emit()

func spawn_cells() -> Array[Vector2i]:
	var map: TileMapLayer = director.world.get_node("Map")
	var terrain := TileGrid.new()
	terrain.setup(map, [])
	var bases: Array[Vector2i] = []
	for building in director.world.registry.all():
		if building is House: bases.append(building.cell)
	var approach: NavigationField = GridSearch.build(terrain, bases, true)
	var shore_fallback: Array[Vector2i] = []
	var shortest_shore := INF
	var candidates: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	var farthest := -1.0
	for cell in terrain.walkable_cells():
		if not director.world.route_service.walkable(cell) or director.world.registry.at(cell) != null: continue
		var distance := INF
		for base in bases:
			if terrain.connected(cell, base): distance = minf(distance, Vector2(cell - base).length())
		if not is_finite(distance): continue
		if distance > farthest:
			farthest = distance
			fallback = [cell]
		elif is_equal_approx(distance, farthest): fallback.append(cell)
		if distance < director.rules.minimum_shore_distance_cells: continue
		for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not terrain.walkable(cell + offset):
				var seconds: float = approach.cost(cell) * director.world.route_service.cell_size() / director.rules.spider_speed
				if seconds < shortest_shore:
					shortest_shore = seconds
					shore_fallback = [cell]
				elif is_equal_approx(seconds, shortest_shore): shore_fallback.append(cell)
				if seconds <= director.rules.maximum_shore_approach_seconds: candidates.append(cell)
				break
	return candidates if not candidates.is_empty() else (shore_fallback if not shore_fallback.is_empty() else (fallback if farthest >= 3.0 else []))
