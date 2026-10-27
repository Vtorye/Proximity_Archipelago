class_name AntMotion
extends RefCounted
## Executes routes using exactly the same terrain speed model used by the planner.
var navigation: RouteService
var route: Route
var finished := true

func follow(next_route: Route) -> void:
	route = next_route
	finished = route == null or not route.is_valid()

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
