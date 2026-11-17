class_name TripPlanner
extends Node

const TIMING := preload("res://game/navigation/navigation_timing.gd")
## World-local assignment policy. Geometry remains in RouteService; hunger stays in AntNeeds.

signal opportunities_changed

const CARRY_SPEED_RATIO := 0.8
const LOAD_PENALTY_SECONDS := 0.5

## Speed as a fraction of normal movement while carrying goods.
@export_range(0.05, 1.0, 0.05) var carry_speed_ratio := CARRY_SPEED_RATIO
## Additional score cost in seconds for each worker assigned to a workplace.
@export_range(0.0, 60.0, 0.1) var load_penalty_seconds := LOAD_PENALTY_SECONDS
var satiety_rules: SatietyRules
var registry: BuildingRegistry
var navigation: RouteService
var inventory: WorldInventory
var logistics: ColonyLogistics
var food_type: ResourceType
var _opportunities_queued := false
var _storage_had_room := true
var _home_fields: Dictionary[Vector2i, NavigationField] = {}
var _revision := -1
var _workplace_revision := -1
var _workplaces_dirty := true
var _work_fields: Dictionary[Vector2i, NavigationField] = {}
var _workplace_components: Dictionary[int, Array] = {}

func configure(buildings: BuildingRegistry, routes: RouteService, stock: WorldInventory, food: ResourceType, colony: ColonyLogistics, rules: SatietyRules) -> void:
	registry = buildings
	navigation = routes
	inventory = stock
	logistics = colony
	food_type = food
	satiety_rules = rules
	registry.changed.connect(refresh_food)
	inventory.changed.connect(_on_inventory_changed)
	registry.added.connect(_on_workplace_membership_changed)
	registry.removed.connect(_on_building_removed)
	navigation.navigation_changed.connect(_on_navigation_changed)

func _on_navigation_changed() -> void:
	if not navigation.last_change_only_cheaper:
		queue_workplace_refresh()

func refresh_food() -> void:
	var cells: Array[Vector2i] = []
	for canteen in registry.canteens():
		cells.append_array(canteen.entry_cells())
	navigation.set_food_cells(cells)

func reserve_meal() -> StockReservation:
	return inventory.reserve(food_type, 1)

func escape_energy(cell: Vector2i, speed: float) -> float:
	return travel_energy(navigation.food_field().cost(cell), speed) + satiety_rules.meal_energy()

func food_within_range(cell: Vector2i, speed: float, capacity: float) -> bool:
	return escape_energy(cell, speed) + satiety_rules.safety_margin <= capacity

func travel_seconds(cost: float, speed: float) -> float:
	return cost * navigation.cell_size() / maxf(speed, 0.01)

func travel_energy(cost: float, speed: float) -> float:
	return travel_seconds(cost, speed) * satiety_rules.walk_rate

func approach_energy(position: Vector2, cell: Vector2i, speed: float) -> float:
	return _approach_seconds(position, cell, speed) * satiety_rules.walk_rate

func _approach_seconds(position: Vector2, cell: Vector2i, speed: float) -> float:
	return position.distance_to(navigation.cell_to_world(cell)) * navigation.entry_cost(cell) / maxf(speed, 0.01)

func plan_work(agent: Node2D, home: Building, needs: AntNeeds, speed: float, work_time: float, ticket: StockReservation, current: Workplace = null, carry_capacity: int = 2) -> WorkPlan:
	if not TIMING.enabled: return _plan_work(agent, home, needs, speed, work_time, ticket, current, carry_capacity)
	TIMING.begin(&"worker_plan")
	var result := _plan_work(agent, home, needs, speed, work_time, ticket, current, carry_capacity)
	TIMING.end()
	return result

func _plan_work(agent: Node2D, home: Building, needs: AntNeeds, speed: float, work_time: float, ticket: StockReservation, current: Workplace = null, carry_capacity: int = 2) -> WorkPlan:
	if not is_instance_valid(home) or (agent is AntAgent and agent.role != AntAgent.Role.WORKER):
		return null
	if not logistics.accepts_home(home as House, 1):
		# Workers do not start a job while their own storage is full.
		var full := WorkPlan.new()
		full.waiting_for_slot = true
		full.waiting_reason = WorkPlan.WaitReason.STORAGE_FULL
		return full
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
	var return_field: NavigationField
	if not foodless:
		if ticket == null or not ticket.active:
			return null
		prepare_home(home)
		return_field = _home_fields[home_cell]
	var outward_field: NavigationField
	if not workplaces.is_empty():
		# A worker can be replanned away from home after construction or wandering.
		outward_field = _work_field(home_cell) if from_cell == home_cell else navigation.distances_from(from_cell)
	var approach := _approach_seconds(agent.global_position, from_cell, speed)
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
			var cost := outward_field.cost(entry)
			if not is_finite(cost): continue
			var to_work: float = approach + travel_seconds(cost, speed)
			var energy: float = to_work * satiety_rules.walk_rate
			var delivery_cost: float = return_field.cost(entry) if not foodless else 0.0
			var work_seconds := work_time
			if workplace.recipe == null:
				var rate: float = workplace.resource_rate()
				if rate <= 0.0: continue
				var capacity_seconds: float = float(carry_capacity) / rate
				var hunger_budget: float
				if foodless:
					hunger_budget = needs.satiety - energy - 0.01
				else:
					var return_energy: float = travel_energy(delivery_cost, speed * carry_speed_ratio) + food_after_home + satiety_rules.travel_reserve + satiety_rules.safety_margin
					hunger_budget = needs.satiety - energy - return_energy
				work_seconds = minf(capacity_seconds, maxf(0.0, hunger_budget / satiety_rules.work_rate))
				if floori(rate * work_seconds + 0.000001) <= 0: continue
			if foodless:
				if energy + work_seconds * satiety_rules.work_rate >= needs.satiety:
					continue
			else:
				energy += _work_return_energy(work_seconds, delivery_cost, food_after_home, speed) + satiety_rules.travel_reserve
				possible_after_meal = possible_after_meal or energy + satiety_rules.safety_margin <= needs.capacity
				if not needs.can_afford(energy):
					continue
			if not workplace.has_worker(agent) and not workplace.has_free_slot():
				feasible_busy = true
				continue
			# Compare other ants; the deciding ant would occupy one slot at either choice.
			var load_count: int = workplace.worker_count() - (1 if workplace.has_worker(agent) else 0)
			var score: float = to_work + load_penalty_seconds * load_count
			if score < best_score or is_equal_approx(score, best_score) and workplace == current:
				best_score = score
				best = WorkPlan.new()
				best.foodless = foodless
				best.workplace = workplace
				best.job_cell = entry
				best.home_cell = home_cell
				best.estimated_energy = energy
				best.work_seconds = work_seconds
				best.navigation_revision = navigation.revision
	if not foodless and best == null and (feasible_busy or not possible_after_meal and needs.can_afford(food_after_home + satiety_rules.travel_reserve)):
		best = WorkPlan.new()
		best.waiting_for_slot = true
		best.waiting_reason = WorkPlan.WaitReason.SLOTS_FULL if feasible_busy else (WorkPlan.WaitReason.MISSING_INPUTS if missing_inputs else WorkPlan.WaitReason.NO_SAFE_WORK)
	if best != null and not best.waiting_for_slot:
		if not best.workplace.has_worker(agent) and not best.workplace.reserve_worker(agent):
			return null
		best.outward = navigation.make_route(outward_field.path(best.job_cell))
	if best != null and is_instance_valid(current) and current != best.workplace:
		current.release_worker(agent)
	return best

## Wake waiting workers only when base storage transitions between full and not full.
func _on_inventory_changed() -> void:
	var has_room: bool = inventory.has_base_room(1)
	if has_room != _storage_had_room:
		_storage_had_room = has_room
		queue_workplace_refresh()

func _on_workplace_membership_changed(building: Building) -> void:
	if not building is Workplace: return
	_workplaces_dirty = true
	queue_workplace_refresh()

func _on_building_removed(building: Building) -> void:
	if building is House:
		for cell in building.entry_cells():
			_work_fields.erase(cell)
			_home_fields.erase(cell)
	_on_workplace_membership_changed(building)

func queue_workplace_refresh() -> void:
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

func can_finish_work(cell: Vector2i, home: Building, needs: AntNeeds, speed: float, remaining_work: float) -> bool:
	if not is_instance_valid(home):
		return false
	var delivery := home_route(home, cell)
	return delivery.is_valid() and needs.can_afford(_work_return_energy(
		remaining_work, delivery.cost, escape_energy(delivery.cells.back(), speed), speed))

func _work_return_energy(work_seconds: float, delivery_cost: float, food_after_delivery: float, speed: float) -> float:
	return work_seconds * satiety_rules.work_rate + travel_energy(delivery_cost, speed * carry_speed_ratio) + food_after_delivery

func prepare_home(home: Building) -> void:
	if _revision != navigation.field_epoch:
		_home_fields.clear()
		_revision = navigation.field_epoch
	var cell: Vector2i = accessible_entry(home)
	if not navigation.walkable(cell):
		return
	_home_fields[cell] = navigation.reverse_field([cell], _home_fields.get(cell))

func home_route(home: Building, from_cell: Vector2i) -> Route:
	prepare_home(home)
	var cell: Vector2i = accessible_entry(home)
	if not _home_fields.has(cell):
		return Route.invalid()
	return navigation.make_route(_home_fields[cell].path(from_cell))

func _work_field(home_cell: Vector2i) -> NavigationField:
	_work_fields[home_cell] = navigation.distances_from(home_cell, _work_fields.get(home_cell))
	return _work_fields[home_cell]

## Work selection starts at the home entrance, so one forward field serves every
## reachable workplace. Only graph invalidation requires a new component index.
func prepare_workplaces() -> void:
	if not _workplaces_dirty and _workplace_revision == navigation.field_epoch:
		return
	var grid: TileGrid = navigation.snapshot()
	if _workplace_revision != navigation.field_epoch:
		_work_fields.clear()
	_workplace_components.clear()
	for workplace in registry.workplaces():
		for entry in workplace.entry_cells():
			var component: int = grid.component(entry)
			if component < 0:
				continue
			if not _workplace_components.has(component):
				_workplace_components[component] = []
			if not _workplace_components[component].has(workplace):
				_workplace_components[component].append(workplace)
	_workplace_revision = navigation.field_epoch
	_workplaces_dirty = false

func _reachable_workplaces(node_id: int) -> Array:
	prepare_workplaces()
	return _workplace_components.get(navigation.snapshot().component_id(node_id), [])
