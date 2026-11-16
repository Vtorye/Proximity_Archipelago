class_name SpiderTrap
extends Node2D
## Persistent enemy hazard. Stepping on it never consumes the trap.
var cell: Vector2i
var director: CombatDirector
const ICON := preload("res://game/assets/sprites/spider_trap.svg")

func trigger(ant: AntAgent) -> void:
	if ant.status == AntAgent.Status.DEAD: return
	ant.take_damage(director.rules.attack_damage if ant.role == AntAgent.Role.WARRIOR else ant.health, AntAgent.DeathCause.TRAP)

func _draw() -> void:
	var size: float = director.world.route_service.cell_size()
	draw_texture_rect(ICON, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false)
