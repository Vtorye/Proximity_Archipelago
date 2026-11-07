class_name AntMotion
extends RefCounted
## Executes routes using exactly the same terrain speed model used by the planner.
var navigation: RouteService
var route: Route
var finished := true

func follow(next_route: Route, position := Vector2(INF, INF)) -> void:
	route = next_route
	finished = route == null or not route.is_valid()
	if finished or navigation == null or not position.is_finite() or route.is_finished(): return
	# Replanning mid-step must not turn the unit back toward a centre it already passed.
	# Finish a centre before a perpendicular turn, so wall corners cannot be cut.
	var center: Vector2 = navigation.cell_to_world(route.current_cell())
	var next: Vector2 = navigation.cell_to_world(route.cells[route.current_index + 1])
	if (position - center).dot(next - center) > 0:
		route.advance()

func step(position: Vector2, speed: float, delta: float) -> Vector2:
	if finished:
		return position
	var budget: float = delta
	for iteration in range(32):
		var target: Vector2 = navigation.cell_to_world(route.current_cell())
		var terrain: float = maxf(0.05, navigation.entry_cost(route.current_cell()))
		var velocity: float = speed / terrain
		var distance: float = position.distance_to(target)
		if distance > velocity * budget:
			return position.move_toward(target, velocity * budget)
		position = target
		budget -= distance / velocity
		if route.is_finished():
			finished = true
			return position
		route.advance()
	return position
