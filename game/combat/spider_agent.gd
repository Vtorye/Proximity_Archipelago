class_name SpiderAgent
extends Node2D
## Mobile predator; target selection and world damage are owned by CombatDirector.
var director: CombatDirector
var health := 6
var motion := AntMotion.new()
var _target: Building
var _retarget := 0.0
var _attack := 0.0
var _last_target_cell := Vector2i(2147483647, 2147483647)
var _revision := -1
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
		if next_target != _target: _last_target_cell = Vector2i(2147483647, 2147483647)
		_target = next_target
		_retarget = 1.0
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
			var stride: int = roundi(sin(_animation * 12 + index) * 1.5)
			draw_line(Vector2(side * 2, index * 2 - 3), Vector2(side * 6, index * 3 - 5 + stride), Color("302326"), 1)
	draw_rect(Rect2(-3, -4, 6, 7), Color("45303c"))
	draw_rect(Rect2(-2, -3, 4, 3), Color("765068"))
	draw_rect(Rect2(-2, 3, 4, 3), Color("31252a"))
	draw_rect(Rect2(-2, 5, 1, 1), Color("f49a80"))
	draw_rect(Rect2(1, 5, 1, 1), Color("f49a80"))
	if health >= director.rules.spider_health: return
	draw_rect(Rect2(-5, -8, 10, 1), Color("292a27"))
	draw_rect(Rect2(-5, -8, 10.0 * health / maxi(1, director.rules.spider_health), 1), Color("e58b76"))

func capture_state() -> Dictionary:
	return {"scene": scene_file_path, "position": position, "health": health, "_attack": _attack}

func restore_state(state: Dictionary) -> void:
	position = state.position
	health = state.health
	_attack = state._attack
