class_name AntVisual
extends Node2D
## Draw the unit and its status indicators from the current simulation state.
var ant: AntAgent
var direction := Vector2.UP
var elapsed := 0.0
var carrying := false

func update_pose(agent: AntAgent, forward: Vector2, time: float, has_cargo: bool) -> void:
	ant = agent
	direction = forward
	elapsed = time
	carrying = has_cargo
	queue_redraw()

func _draw() -> void:
	if ant == null:
		return
	var sprite: Node2D = ant.authored_sprite()
	# Pixel-native ant art remains crisp at every integer camera zoom.
	if sprite != null:
		sprite.visible = ant.status not in [AntAgent.Status.HOME, AntAgent.Status.DEAD]
		sprite.rotation = direction.angle() + PI * 0.5
	if ant.status == AntAgent.Status.HOME or ant.status == AntAgent.Status.DEAD:
		return
	var forward: Vector2 = direction
	var side := Vector2(-forward.y, forward.x)
	if sprite == null:
		var leg_phase: float = sin(elapsed * 22.0) if ant.status == AntAgent.Status.WALKING else 0.0
		for pair in range(3):
			var origin: Vector2 = forward * (pair - 1) * 2.0
			for sign_value in [-1.0, 1.0]:
				var foot: Vector2 = origin + side * sign_value * 3.5 + forward * leg_phase * sign_value
				draw_line(origin, foot.round(), Color("222521"), 1.0)
		var abdomen := Color("a87054") if ant.role == AntAgent.Role.WARRIOR else (Color("50677b") if ant.role == AntAgent.Role.CARRIER else Color("38271e"))
		draw_circle(-forward * 3.0, 2.0, abdomen)
		draw_circle(Vector2.ZERO, 1.5, Color("241e19"))
		draw_circle(forward * 3.0, 1.7, Color("33251d"))
		for sign_value in [-1.0, 1.0]:
			draw_line(forward * 4.0, (forward * 6.0 + side * sign_value * 2.0).round(), Color("241e19"), 1.0)
	if carrying:
		draw_rect(Rect2(Vector2(-1, -6), Vector2(3, 3)), Color("d7bc73"))
	if ant.health < ant.max_health:
		draw_rect(Rect2(-4, -10, 8, 1), Color("38271e"))
		draw_rect(Rect2(-4, -10, 8.0 * ant.health / ant.max_health, 1), Color("e58b76"))
	if ant.needs.fraction() < 0.25:
		draw_rect(Rect2(-4, -8, 8, 1), Color("38271e"))
		draw_rect(Rect2(-4, -8, 8 * ant.needs.fraction(), 1), Color("edb86c"))

