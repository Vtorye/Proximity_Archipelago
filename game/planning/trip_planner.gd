class_name TripPlanner
extends Node
## World-local assignment policy. Geometry remains in RouteService; hunger stays in AntNeeds.

signal opportunities_changed

const CARRY_SPEED_RATIO := 0.8
const LOAD_PENALTY_SECONDS := 0.5
var registry: BuildingRegistry
var navigation: RouteService
var inventory: WorldInventory
var food_type: ResourceType
var _opportunities_queued := false
var _home_fields: Dictionary[Vector2i, NavigationField] = {}
var _revision := -1
var _workplace_revision := -1
var _workplaces_dirty := true
var _work_fields: Dictionary[Vector2i, NavigationField] = {}
var _workplace_components: Dictionary[int, Array] = {}

func configure(buildings: BuildingRegistry, routes: RouteService, stock: WorldInventory, food: ResourceType) -> void:
	registry = buildings
	navigation = routes
	inventory = stock
	food_type = food
	registry.changed.connect(refresh_food)
	registry.added.connect(_on_workplace_membership_changed)
	registry.removed.connect(_on_workplace_membership_changed)
	navigation.navigation_changed.connect(_queue_workplace_refresh)

func refresh_food() -> void:
	var cells: Array[Vector2i] = []
	for canteen in registry.canteens():
		cells.append_array(canteen.entry_cells())
	navigation.set_food_cells(cells)

func reserve_meal() -> StockReservation:
	return inventory.reserve(food_type, 1)

func escape_energy(cell: Vector2i, speed: float) -> float:
	return travel_energy(navigation.food_field().cost(cell), speed) + AntNeeds.MEAL_SECONDS * AntNeeds.EAT_RATE

func food_within_range(cell: Vector2i, speed: float, capacity: float = AntNeeds.CAPACITY) -> bool:
	return escape_energy(cell, speed) + AntNeeds.SAFETY_MARGIN <= capacity

func travel_seconds(cost: float, speed: float) -> float:
	return cost * navigation.cell_size() / maxf(speed, 0.01)

func travel_energy(cost: float, speed: float) -> float:
	return travel_seconds(cost, speed) * AntNeeds.WALK_RATE

func plan_work(agent: Node2D, home: Building, needs: AntNeeds, speed: float, work_time: float, ticket: StockReservation, current: Workplace = null) -> WorkPlan:
	if not is_instance_valid(home) or (agent is AntAgent and agent.role != AntAgent.Role.WORKER):
		return null
	var home_cell: Vector2i = accessible_entry(home)
	if not navigation.walkable(home_cell):
		return null
	var from_cell: Vector2i = navigation.world_to_cell(agent.global_position)
	var from_node: int = navigation.snapshot().index(from_cell)
	if from_node < 0:
		return null
	var foodless: bool = not food_within_range(from_cell, speed, needs.capacity)
	var workplaces: Array = _reachable_workplaces(from_node)
	if foodless and workplaces.is_empty():
		return null
	var home_field: NavigationField
	if not foodless:
		if ticket == null or not ticket.active:
			return null
		prepare_home(home)
		home_field = _home_fields[home_cell]
	var approach: float = agent.global_position.distance_to(navigation.cell_to_world(from_cell)) * navigation.entry_cost(from_cell) / maxf(speed, 0.01)
	var food_after_home: float = escape_energy(home_cell, speed) if not foodless else INF
	var best_score := INF
	var best: WorkPlan
	var feasible_busy := false
	var missing_inputs := false
	var possible_after_meal := false
	for workplace: Workplace in workplaces:
		if not workplace.can_run_recipe():
			missing_inputs = true
			continue
		for entry: Vector2i in workplace.entry_cells():
			var field: NavigationField = _work_fields.get(entry)
			if field == null:
				continue
			var to_work: float = approach + travel_seconds(field.cost_at_node(from_node), speed)
			var energy: float = to_work * AntNeeds.WALK_RATE
			if foodless:
				if energy >= needs.satiety:
					continue
			else:
				var back_home: float = travel_energy(home_field.cost(entry), speed * CARRY_SPEED_RATIO)
				energy += work_time * AntNeeds.WORK_RATE + back_home + food_after_home + 2.0
				possible_after_meal = possible_after_meal or energy + AntNeeds.SAFETY_MARGIN <= needs.capacity
				if not needs.can_afford(energy):
					continue
			if not workplace.has_worker(agent) and not workplace.has_free_slot():
				feasible_busy = true
				continue
			# Compare other ants; the deciding ant would occupy one slot at either choice.
			var load_count: int = workplace.worker_count() - (1 if workplace.has_worker(agent) else 0)
			var score: float = to_work + LOAD_PENALTY_SECONDS * load_count
			if score < best_score or is_equal_approx(score, best_score) and workplace == current:
				best_score = score
				best = WorkPlan.new()
				best.foodless = foodless
				best.workplace = workplace
				best.job_cell = entry
				best.home_cell = home_cell
				best.estimated_energy = energy
				best.navigation_revision = navigation.revision
	if not foodless and best == null and (feasible_busy or not possible_after_meal and needs.can_afford(food_after_home + 2.0)):
		best = WorkPlan.new()
		best.waiting_for_slot = true
		best.waiting_reason = WorkPlan.WaitReason.SLOTS_FULL if feasible_busy else (WorkPlan.WaitReason.MISSING_INPUTS if missing_inputs else WorkPlan.WaitReason.NO_SAFE_WORK)
	if best != null and not best.waiting_for_slot:
		if not best.workplace.has_worker(agent) and not best.workplace.reserve_worker(agent):
			return null
		best.outward = navigation.make_route(_work_fields[best.job_cell].path(from_cell))
	if best != null and is_instance_valid(current) and current != best.workplace:
		current.release_worker(agent)
	return best

func _on_workplace_membership_changed(building: Building) -> void:
	if not building is Workplace: return
	_workplaces_dirty = true
	_queue_workplace_refresh()

func _queue_workplace_refresh() -> void:
	if _opportunities_queued: return
	_opportunities_queued = true
	_refresh_workplaces.call_deferred()

func _refresh_workplaces() -> void:
	_opportunities_queued = false
	prepare_workplaces()
	opportunities_changed.emit()

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

func home_route(home: Building, from_cell: Vector2i) -> Route:
	prepare_home(home)
	var cell: Vector2i = accessible_entry(home)
	if not _home_fields.has(cell):
		return Route.invalid()
	return navigation.make_route(_home_fields[cell].path(from_cell))

## Each walkable entrance owns a reverse field on the shared island graph.
## Keep fields for existing entrances when only the workplace list changes.
func prepare_workplaces() -> void:
	if not _workplaces_dirty and _workplace_revision == navigation.revision:
		return
	var grid: TileGrid = navigation.snapshot()
	var fields: Dictionary[Vector2i, NavigationField] = {}
	_workplace_components.clear()
	for workplace in registry.workplaces():
		for entry in workplace.entry_cells():
			var component: int = grid.component(entry)
			if component < 0:
				continue
			if not fields.has(entry):
				var previous: NavigationField = _work_fields.get(entry) if _workplace_revision == navigation.revision else null
				fields[entry] = previous if previous != null else navigation.reverse_field([entry])
			if not _workplace_components.has(component):
				_workplace_components[component] = []
			if not _workplace_components[component].has(workplace):
				_workplace_components[component].append(workplace)
	_work_fields = fields
	_workplace_revision = navigation.revision
	_workplaces_dirty = false

func _reachable_workplaces(node_id: int) -> Array:
	prepare_workplaces()
	return _workplace_components.get(navigation.snapshot().component_id(node_id), [])
