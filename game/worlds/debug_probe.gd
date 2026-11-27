class_name DebugProbe
extends Node
## Debug-only observer. Changes no game state.
## Logs unit spawns, deaths, status transitions, building setup/demolish/build and periodic summaries.
## Output goes to the Godot console and a separate user:// log for this session.

@export var enabled := false
@export var summary_interval := 5.0
var _world: World
var _file: FileAccess
var _timer := 0.0

func configure(world: World) -> void:
	_world = world

func _ready() -> void:
	if not enabled or _world == null:
		set_process(false)
		return
	var path: String = "user://colony-%d.log" % Time.get_ticks_usec()
	_file = FileAccess.open(path, FileAccess.WRITE)
	_world.population.spawned.connect(_observe_agent)
	_world.registry.added.connect(func(building: Building): _log("building", "registered %s at %s" % [building.name, building.cell]))
	_world.registry.removed.connect(func(building: Building): _log("building", "removed %s" % building.name))
	for ant in _world.population.agents():
		_observe_agent(ant)
	_log("probe", "started: %s" % path)

func _observe_agent(ant: AntAgent) -> void:
	ant.status_changed.connect(_on_status.bind(ant))
	ant.died.connect(func(agent: Node2D, cause: int): _log("death", "%s cause=%d" % [agent.name, cause]))
	_log("spawn", "%s %s" % [ant.name, JSON.stringify(ant.debug_snapshot())])

func _on_status(_status: int, ant: AntAgent) -> void:
	_log("status", "%s %s" % [ant.name, JSON.stringify(ant.debug_snapshot())])

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= summary_interval:
		_timer = 0.0
		_log("summary", "ants=%d searches=%d cache_hits=%d" % [_world.population.count(), _world.route_service.search_count, _world.route_service.cache_hits])
		if _file != null:
			_file.flush()

func _log(category: String, message: String) -> void:
	var line: String = "[frame %d][%s] %s" % [Engine.get_process_frames(), category, message]
	print(line)
	if _file != null:
		_file.store_line(line)

func _exit_tree() -> void:
	if _file != null:
		_file.flush()
		_file = null
