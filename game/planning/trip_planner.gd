class_name TripPlanner
extends Node
## World-local assignment policy. Geometry remains in RouteService; hunger stays in AntNeeds.

const CARRY_SPEED_RATIO := 0.8
var registry: BuildingRegistry
var navigation: RouteService
var inventory: WorldInventory
var food_type: ResourceType
var _home_fields: Dictionary[Vector2i, NavigationField] = {}
var _revision := -1

func configure(buildings: BuildingRegistry, routes: RouteService, stock: WorldInventory, food: ResourceType) -> void:
	registry = buildings
	navigation = routes
	inventory = stock
	food_type = food
	registry.changed.connect(refresh_food)

func refresh_food() -> void:
	var cells: Array[Vector2i] = []
	for canteen in registry.canteens():
		cells.append_array(canteen.entry_cells())
	navigation.set_food_cells(cells)

func reserve_meal() -> StockReservation:
	return inventory.reserve(food_type, 1)

func escape_energy(cell: Vector2i, speed: float) -> float:
	return travel_energy(navigation.food_field().cost(cell), speed) + AntNeeds.MEAL_SECONDS * AntNeeds.EAT_RATE

func travel_energy(cost: float, speed: float) -> float:
	return cost * navigation.cell_size() / maxf(speed, 0.01) * AntNeeds.WALK_RATE

func plan_work(agent: Node2D, home: Building, needs: AntNeeds, speed: float, work_time: float, ticket: StockReservation) -> WorkPlan:
	if ticket == null or not ticket.active or not is_instance_valid(home):
		return null
	var home_cell: Vector2i = accessible_entry(home)
	if not navigation.walkable(home_cell):
		return null
	prepare_home(home)
	var home_field: NavigationField = _home_fields[home_cell]
	var from_cell: Vector2i = navigation.world_to_cell(agent.global_position)
	var outward: NavigationField = navigation.distances_from(from_cell)
	var food_after_home: float = escape_energy(home_cell, speed)
	var best_score := INF
	var best: WorkPlan
	var feasible_busy := false
	var possible_after_meal := false
	for workplace in registry.workplaces():
		for entry in workplace.entry_cells():
			var to_work: float = travel_energy(outward.cost(entry), speed)
			var back_home: float = travel_energy(home_field.cost(entry), speed * CARRY_SPEED_RATIO)
			var energy: float = to_work + work_time * AntNeeds.WORK_RATE + back_home + food_after_home + 2.0
			possible_after_meal = possible_after_meal or energy + AntNeeds.SAFETY_MARGIN <= AntNeeds.CAPACITY
			if not needs.can_afford(energy):
				continue
			if not workplace.has_free_slot():
				feasible_busy = true
				continue
			var stock_level: float = inventory.quantity(workplace.output) if workplace.output != null else 100000.0
			var score: float = stock_level / maxf(1.0, workplace.output_amount) + to_work * 0.25
			if score < best_score:
				best_score = score
				best = WorkPlan.new()
				best.workplace = workplace
				best.outward = navigation.make_route(outward.path(entry))
				best.job_cell = entry
				best.home_cell = home_cell
				best.estimated_energy = energy
				best.navigation_revision = navigation.revision
	if best == null and (feasible_busy or not possible_after_meal and needs.can_afford(food_after_home + 2.0)):
		best = WorkPlan.new()
		best.waiting_for_slot = true
	if best != null and not best.waiting_for_slot and not best.workplace.reserve_worker(agent):
		return null
	return best

func accessible_entry(building: Building) -> Vector2i:
	for cell in building.entry_cells():
		if navigation.walkable(cell):
			return cell
	return Vector2i(2147483647, 2147483647)

func food_route(from_cell: Vector2i) -> Route:
	return navigation.make_route(navigation.food_field().path(from_cell))

func can_finish_work(cell: Vector2i, needs: AntNeeds, speed: float, remaining_work: float) -> bool:
	return needs.can_afford(remaining_work * AntNeeds.WORK_RATE + escape_energy(cell, speed * CARRY_SPEED_RATIO))

func prepare_home(home: Building) -> void:
	if _revision != navigation.revision:
		_home_fields.clear()
		_revision = navigation.revision
	var cell: Vector2i = accessible_entry(home)
	if not navigation.walkable(cell):
		return
	if not _home_fields.has(cell):
		if _home_fields.size() >= 8:
			_home_fields.erase(_home_fields.keys()[0])
		_home_fields[cell] = navigation.reverse_field([cell])
	navigation.distances_from(cell)

func home_route(home: Building, from_cell: Vector2i) -> Route:
	prepare_home(home)
	var cell: Vector2i = accessible_entry(home)
	if not _home_fields.has(cell):
		return Route.invalid()
	return navigation.make_route(_home_fields[cell].path(from_cell))
