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
	if _revision != navigation.revision:
		_home_fields.clear()
		_revision = navigation.revision
	var home_cell: Vector2i = accessible_entry(home)
	if not navigation.walkable(home_cell):
		return null
	if not _home_fields.has(home_cell):
		if _home_fields.size() >= 8:
			_home_fields.erase(_home_fields.keys()[0])
		_home_fields[home_cell] = navigation.reverse_field([home_cell])
	var home_field: NavigationField = _home_fields[home_cell]
	var from_cell: Vector2i = navigation.world_to_cell(agent.global_position)
	var outward: NavigationField = navigation.distances_from(from_cell)
	var food_after_home: float = escape_energy(home_cell, speed)
	var best_score := INF
	var best: WorkPlan
	for workplace in registry.workplaces():
		if not workplace.has_free_slot():
			continue
		for entry in workplace.entry_cells():
			var to_work: float = travel_energy(outward.cost(entry), speed)
			var back_home: float = travel_energy(home_field.cost(entry), speed * CARRY_SPEED_RATIO)
			var energy: float = to_work + work_time * AntNeeds.WORK_RATE + back_home + food_after_home + 2.0
			if not needs.can_afford(energy):
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
	if best != null and not best.workplace.reserve_worker(agent):
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
