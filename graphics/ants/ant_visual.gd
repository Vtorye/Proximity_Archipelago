class_name AntVisual
extends Node2D
## Draw the unit and its status indicators from the current simulation state.
@export var worker_appearance: WorkerAppearance = preload("res://graphics/ants/worker_appearance.tres")
@export var cargo_marker := Rect2(-1, -6, 3, 3)
@export var health_bar := Rect2(-4, -10, 8, 1)
@export var satiety_bar := Rect2(-4, -8, 8, 1)
@export_range(0.0, 1.0, 0.01) var satiety_bar_threshold := 0.25
@export_range(0.0, 60.0, 0.1, "or_greater") var stride_frequency := 22.0

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
		var leg_phase: float = sin(elapsed * stride_frequency) if ant.status == AntAgent.Status.WALKING else 0.0
		for pair in range(3):
			var origin: Vector2 = forward * (pair - 1) * 2.0
			for sign_value in [-1.0, 1.0]:
				var foot: Vector2 = origin + side * sign_value * 3.5 + forward * leg_phase * sign_value
				draw_line(origin, foot.round(), ColonyStyle.color(&"map_ant_legs"), 1.0)
		var abdomen: Color = worker_appearance.abdomen_color
		match ant.role:
			AntAgent.Role.WARRIOR: abdomen = ColonyStyle.color(&"warrior_abdomen")
			AntAgent.Role.CARRIER: abdomen = ColonyStyle.color(&"carrier_abdomen")
		draw_circle(-forward * 3.0, 2.0, abdomen)
		draw_circle(Vector2.ZERO, 1.5, ColonyStyle.color(&"map_ant_thorax"))
		draw_circle(forward * 3.0, 1.7, ColonyStyle.color(&"map_ant_head"))
		for sign_value in [-1.0, 1.0]:
			draw_line(forward * 4.0, (forward * 6.0 + side * sign_value * 2.0).round(), ColonyStyle.color(&"map_ant_thorax"), 1.0)
	if carrying:
		draw_rect(cargo_marker, ColonyStyle.color(&"carried_goods"))
	if ant.health < ant.max_health:
		draw_rect(health_bar, ColonyStyle.color(&"ant_bar_background"))
		draw_rect(Rect2(health_bar.position, Vector2(health_bar.size.x * ant.health / ant.max_health, health_bar.size.y)), ColonyStyle.color(&"health_fill"))
	if ant.needs.fraction() < satiety_bar_threshold:
		draw_rect(satiety_bar, ColonyStyle.color(&"ant_bar_background"))
		draw_rect(Rect2(satiety_bar.position, Vector2(satiety_bar.size.x * ant.needs.fraction(), satiety_bar.size.y)), ColonyStyle.color(&"satiety_fill"))
