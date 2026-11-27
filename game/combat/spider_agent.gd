class_name SpiderAgent
extends Node2D
## Mobile predator; target selection and world damage are owned by CombatDirector.
var director: CombatDirector
var health: int
var motion := AntMotion.new()
var _target: Node2D
var _retarget := 0.0
var _attack := 0.0
var _last_target_cell := TileGrid.NO_CELL
var _revision := -1
@export_group("Appearance")
@export var body_shape := Rect2(-3, -4, 6, 7)
@export var marking_shape := Rect2(-2, -3, 4, 3)
@export var head_shape := Rect2(-2, 3, 4, 3)
@export var eyes: Array[Rect2] = [Rect2(-2, 5, 1, 1), Rect2(1, 5, 1, 1)]
@export var health_bar := Rect2(-5, -8, 10, 1)
@export_range(0.0, 32.0, 0.1, "or_greater") var stride_frequency := 12.0
@export_range(0.0, 8.0, 0.1, "or_greater") var stride_amplitude := 1.5

var _animation := 0.0

func _ready() -> void:
	motion.navigation = director.world.route_service
	health = director.rules.spider_health

func take_damage(amount: int) -> void:
	if health <= 0 or amount <= 0: return
	health = maxi(0, health - amount)
	queue_redraw()
	if health == 0:
		director.remove_spider(self)
		queue_free()

func _physics_process(delta: float) -> void:
	if health <= 0 or not director.running(): return
	_animation += delta
	_attack = maxf(0.0, _attack - delta)
	var navigation: RouteService = director.world.route_service
	var cell: Vector2i = navigation.world_to_cell(global_position)
	_retarget -= delta
	if _retarget <= 0 or not director.is_spider_target(_target):
		var next_target := director.prey(cell)
		if next_target != _target: _last_target_cell = TileGrid.NO_CELL
		_target = next_target
		_retarget = director.rules.spider_retarget_seconds
	if not director.is_spider_target(_target): return
	if director.can_melee(global_position, _target):
		if _attack <= 0:
			director.damage(_target, director.rules.attack_damage)
			_attack = director.rules.attack_seconds
	else:
		var target_cell: Vector2i = navigation.world_to_cell(_target.global_position)
		if target_cell != _last_target_cell or _revision != navigation.revision:
			motion.follow(director.approach(_target, cell), global_position)
			_last_target_cell = target_cell
			_revision = navigation.revision
		if motion.route != null and motion.route.is_valid():
			global_position = motion.step(global_position, director.rules.spider_speed, delta)
	queue_redraw()

func _draw() -> void:
	for side in [-1, 1]:
		for index in range(4):
			var stride: int = roundi(sin(_animation * stride_frequency + index) * stride_amplitude)
			draw_line(Vector2(side * 2, index * 2 - 3), Vector2(side * 6, index * 3 - 5 + stride), ColonyStyle.color(&"spider_legs"), 1)
	draw_rect(body_shape, ColonyStyle.color(&"spider_body"))
	draw_rect(marking_shape, ColonyStyle.color(&"spider_marking"))
	draw_rect(head_shape, ColonyStyle.color(&"spider_head"))
	for eye in eyes:
		draw_rect(eye, ColonyStyle.color(&"spider_eyes"))
	if health >= director.rules.spider_health: return
	draw_rect(health_bar, ColonyStyle.color(&"enemy_bar_background"))
	draw_rect(Rect2(health_bar.position, Vector2(health_bar.size.x * health / maxi(1, director.rules.spider_health), health_bar.size.y)), ColonyStyle.color(&"health_fill"))

func capture_state() -> Dictionary:
	return {"scene": scene_file_path, "position": position, "health": health, "_attack": _attack}

func restore_state(state: Dictionary) -> void:
	position = state.position
	health = state.health
	_attack = state._attack
