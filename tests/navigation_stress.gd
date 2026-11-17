extends Node2D
## Run with --max-fps 60 res://tests/navigation_stress.tscn -- <case index>.
## Measure without --write-movie; Movie Maker fixes the simulation time step.
const CASES := [
	Vector4i(30, 6, 18, 48),
	Vector4i(60, 12, 36, 96),
	Vector4i(120, 24, 72, 192),
	Vector4i(240, 40, 120, 320),
	Vector4i(10, 2, 6, 16),
	Vector4i(20, 4, 12, 32),
]
const MAP_SIZE := Vector2i(48, 23)
const ROAD := preload("res://game/building/options/road.tres")
const TIMING := preload("res://game/navigation/navigation_timing.gd")
const RUN_SECONDS := 32.0
const WALL_LIMIT_SECONDS := 45.0

var world: World
var scenario: Vector4i
var elapsed := 0.0
var last_tick := 0
var start_tick := 0
var movie := false
var committed := false
var setup_ms := 0.0
var commit_ms := 0.0
var road_cells: Array[Vector2i] = []
var completed := 0
var revision := 0
var searches := 0
var idle_frames: Array[float] = []
var build_frames: Array[float] = []
var road_frames: Array[float] = []
var last_completed := 0
var map_seed := -1
var active_workers: Dictionary[int, bool] = {}
var slow_frames: Array[Dictionary] = []
var profiling := false

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	seed(412)
	var args := OS.get_cmdline_user_args()
	movie = args.has("movie")
	profiling = args.has("profile")
	for arg in args:
		if arg.begins_with("seed="): map_seed = int(arg.trim_prefix("seed="))
	scenario = CASES[clampi(int(args[0]), 0, CASES.size() - 1)] if not args.is_empty() else CASES[0]
	world = _generated_world() if map_seed >= 0 else _flat_world()
	if world == null:
		push_error("Invalid stress level")
		get_tree().quit(2)
		return
	world.auto_start = false
	world.task_deck = null
	add_child(world)
	if world.route_service == null or world.logistics.nests().size() != scenario.y or world.registry.workplaces().size() < scenario.z:
		push_error("Missing stress fixture buildings")
		get_tree().quit(2)
		return
	var houses := world.logistics.nests()
	for i in range(scenario.x - houses.size()):
		world.population.restore_resident(houses[i % houses.size()], AntAgent.Role.CARRIER)
	for ant in world.population.agents():
		if ant.role == AntAgent.Role.WORKER:
			ant.work_completed.connect(func(worker: Node2D, _place: Node2D): active_workers[worker.get_instance_id()] = true)
	var wood := world.inventory.type_by_id(&"wood")
	var wood_stock := ResourceAmount.new()
	wood_stock.type = wood
	wood_stock.amount = scenario.w * 12
	world.inventory.deposit(null, [wood_stock], true)
	_pick_roads()
	var count := world.population.agents().filter(func(ant: AntAgent) -> bool: return ant.role == AntAgent.Role.CARRIER).size()
	if count != scenario.x or road_cells.size() != scenario.w:
		push_error("Stress fixture did not reach the requested load")
		get_tree().quit(2)
		return
	var region := world.map.get_used_rect()
	$Camera2D.position = Vector2(region.get_center()) * world.route_service.cell_size()
	$Camera2D.zoom = Vector2.ONE * (0.8 if map_seed < 0 else 22.0 / region.size.y)
	world.build_controller.built.connect(func(option: BuildOption, _cell: Vector2i):
		if option == ROAD: completed += 1)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	revision = world.route_service.revision
	searches = world.route_service.search_count
	TIMING.enabled = profiling
	last_tick = Time.get_ticks_usec()
	start_tick = last_tick

func _flat_world() -> World:
	var tiles: Array = []
	var objects: Array = [[2, 3, "build/base_nest"], [2, 1, "Food"]]
	for y in range(MAP_SIZE.y):
		for x in range(MAP_SIZE.x):
			tiles.append([x, y, 3, 0, 0, 0])
	for i in range(1, scenario.y):
		objects.append([2 + i % 10 * 4, 3 + (i / 10) * 4, "build/house"])
	for i in range(scenario.z):
		objects.append([2 + i % 43, 5 + (i / 43) * 4, "build/apple_tree"])
	return LevelLayout.create_world({"version": 1, "tiles": tiles, "objects": objects})

func _generated_world() -> World:
	var template := LevelLayout.DEFAULT_WORLD.instantiate() as World
	var data := IslandGenerator.generate_data(template, map_seed, 0, map_seed % 3, 80)
	template.free()
	if data == null: return null
	var generated := LevelLayout.instantiate_world(data)
	if generated == null: return null
	var grid := TileGrid.new()
	grid.setup(generated.map, [])
	var center: Vector2i = data.objects.front().cell
	var occupied: Dictionary[Vector2i, bool] = {}
	var workplaces := 0
	for building in generated.placed_buildings():
		for cell in building.footprint(): occupied[cell] = true
		if building is Workplace: workplaces += 1
	var candidates: Array[Vector2i] = []
	for cell in grid.walkable_cells():
		if grid.connected(center, cell) and Vector2(center - cell).length() <= 15.0 and not occupied.has(cell):
			candidates.append(cell)
	generated.free()
	candidates.sort()
	candidates.shuffle()
	var catalog := preload("res://game/terrain/catalog.tres")
	var nests := 1
	for cell in candidates:
		var ground := catalog.for_tile(data.tiles[cell])
		if nests < scenario.y and TerrainRules.supports(ground, BuildOption.PlacementKind.NEST):
			data.objects.append(LevelData.Placement.new(cell, "build/house"))
			occupied[cell] = true
			nests += 1
	for cell in candidates:
		if workplaces >= scenario.z: break
		if occupied.has(cell) or not TerrainRules.supports(catalog.for_tile(data.tiles[cell]), BuildOption.PlacementKind.BERRY):
			continue
		data.objects.append(LevelData.Placement.new(cell, "build/apple_tree"))
		workplaces += 1
	return LevelLayout.instantiate_world(data)

func _pick_roads() -> void:
	if map_seed >= 0:
		var base := world.logistics.main_nest.cell
		var grid := world.route_service.snapshot()
		var candidates: Array[Vector2i] = []
		for cell in grid.walkable_cells():
			if grid.connected(base, cell) and Vector2(base - cell).length() <= 12.0:
				if world.registry.at(cell) == null and world.build_controller.placement_check(ROAD, cell).allowed():
					candidates.append(cell)
		candidates.sort()
		candidates.shuffle()
		road_cells.assign(candidates.slice(0, scenario.w))
		return
	for y in range(MAP_SIZE.y):
		for x in range(2, MAP_SIZE.x - 2):
			var cell := Vector2i(x, y)
			if world.registry.at(cell) == null and world.build_controller.placement_check(ROAD, cell).allowed():
				road_cells.append(cell)
				if road_cells.size() == scenario.w: break
		if road_cells.size() == scenario.w: break
	var count := world.population.agents().filter(func(ant: AntAgent) -> bool: return ant.role == AntAgent.Role.CARRIER).size()

func _process(delta: float) -> void:
	if last_tick == 0: return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - last_tick) / 1000.0
	last_tick = now
	elapsed += delta
	if profiling:
		var sample := TIMING.sample()
		if committed and frame_ms >= 50.0:
			sample["frame_ms"] = frame_ms
			sample["roads_done"] = completed - last_completed
			slow_frames.append(sample)
	if committed:
		build_frames.append(frame_ms)
		if completed != last_completed: road_frames.append(frame_ms)
	elif elapsed >= 0.5:
		idle_frames.append(frame_ms)
	last_completed = completed
	var header := "%d couriers   %d nests   %d workplaces\nRoads finished %d / %d   |   %5.1f s" % [
		scenario.x, scenario.y, scenario.z, completed, scenario.w, elapsed]
	$HUD/Metrics.text = header + ("\nFixed-step replay" if movie else "\nFrame %5.1f ms   |   Queue commit %5.1f ms" % [frame_ms, commit_ms])
	if not committed and elapsed >= 2.0:
		_queue_roads()
	if elapsed >= RUN_SECONDS or (not movie and now - start_tick >= WALL_LIMIT_SECONDS * 1000000.0):
		_report()

func _queue_roads() -> void:
	var draft := BuildDraft.new()
	draft.controller = world.build_controller
	var start := Time.get_ticks_usec()
	for cell in road_cells:
		if not draft.paint(ROAD, cell):
			push_error("Road placement rejected at %s" % [cell])
			get_tree().quit(2)
			return
	setup_ms = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	committed = draft.commit()
	commit_ms = (Time.get_ticks_usec() - start) / 1000.0
	if not committed or world.build_controller.construction.sites.size() != scenario.w:
		push_error("Road batch did not create %d sites (%s)" % [scenario.w, draft.last_result.code])
		get_tree().quit(2)

func _report() -> void:
	if profiling:
		TIMING.enabled = false
		print("NAV PROFILE ", JSON.stringify(slow_frames))
	print("NAV STRESS ", JSON.stringify({
		"couriers": scenario.x, "nests": scenario.y, "workplaces": world.registry.workplaces().size(), "roads_queued": scenario.w,
		"map_seed": map_seed, "workers_completed_work": active_workers.size(), "land_cells": world.route_service.snapshot().node_count(),
		"roads_finished": completed, "live_ants": world.population.count(),
		"simulation_seconds": elapsed, "wall_seconds": (last_tick - start_tick) / 1000000.0,
		"live_couriers": world.population.agents().filter(func(ant: AntAgent) -> bool: return ant.role == AntAgent.Role.CARRIER).size(),
		"paint_ms": setup_ms, "commit_ms": commit_ms, "navigation_revisions": world.route_service.revision - revision,
		"searches": world.route_service.search_count - searches,
		"idle_frames": _frame_stats(idle_frames), "build_frames": _frame_stats(build_frames),
		"road_completion_frames": _frame_stats(road_frames),
	}))
	get_tree().quit(0 if completed > 0 and world.route_service.revision > revision else 2)

static func _frame_stats(samples: Array[float]) -> Dictionary:
	if samples.is_empty(): return {}
	samples.sort()
	return {
		"p95_ms": samples[floori((samples.size() - 1) * 0.95)],
		"p99_ms": samples[floori((samples.size() - 1) * 0.99)],
		"max_ms": samples.back(), "count": samples.size(),
		"over_50_ms": samples.filter(func(ms: float) -> bool: return ms >= 50.0).size(),
		"over_100_ms": samples.filter(func(ms: float) -> bool: return ms >= 100.0).size(),
	}
