class_name AntWork
extends RefCounted
## Owns the current workplace, its reserved slot and execution of the work plan.

var ant: AntAgent
var workplace: Workplace
var plan: WorkPlan
var waiting_for_work := false

func decide(foodless: bool) -> void:
	if foodless:
		ant.transport.carrying = false
	plan = ant.planner.plan_work(ant, ant.home, ant.needs, ant.speed, ant.work_time, ant._meal, workplace, ant.carry_capacity)
	if plan != null and plan.waiting_for_slot:
		waiting_for_work = true
		ant._set_waiting_reason(plan.waiting_reason)
		release()
		if ant.global_position.distance_squared_to(ant.route_service.cell_to_world(ant.planner.accessible_entry(ant.home))) > 0.01:
			ant._go_home()
		else:
			ant._set_status(AntAgent.Status.HOME)
			ant._timer = ant.definition.work_queue_wait_seconds
	elif plan != null:
		waiting_for_work = false
		ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
		workplace = plan.workplace
		ant._walk(plan.outward, &"work")
	else:
		waiting_for_work = false
		ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
		if foodless:
			release()
			ant._wander()
		else:
			ant._seek_food()

func tick(delta: float) -> bool:
	ant._timer -= delta
	if not is_instance_valid(workplace) or not workplace.is_inside_tree():
		ant._seek_food()
	elif ant._timer <= 0.0:
		if not workplace.complete_work_period(ant, plan.work_seconds, true):
			# Contended ingredients must not trap the worker in unbudgeted repeat cycles.
			ant._seek_food()
			return false
		ant.transport.cargo = workplace.take_output(ant.carry_capacity)
		ant.work_completed.emit(ant, workplace)
		if not ant.transport.cargo.is_empty():
			release()
			ant.transport.deliver()
		elif plan != null and plan.foodless and not ant._can_recover():
			ant._timer = ant.work_time
		else:
			release()
			ant._go_home()
	return true

func arrive() -> void:
	var cell: Vector2i = ant.route_service.world_to_cell(ant.global_position)
	if plan == null or not is_instance_valid(workplace) or not ant.planner.can_finish_work(cell, ant.home, ant.needs, ant.speed, plan.work_seconds, plan.foodless) or not workplace.begin_work(ant):
		ant._seek_food()
		return
	ant._set_status(AntAgent.Status.WORKING)
	ant._timer = plan.work_seconds

func reconsider() -> void:
	if plan == null:
		return
	if plan.foodless and ant._can_recover():
		ant._seek_food()
		return
	if not plan.foodless and ant._is_foodless():
		plan.foodless = true
		ant.planner.inventory.release(ant._meal)
		ant._meal = null
	var cell := ant.route_service.world_to_cell(ant.global_position)
	if not ant.planner.can_finish_work(cell, ant.home, ant.needs, ant.speed, ant._timer, plan.foodless):
		ant._seek_food()

func release() -> void:
	if is_instance_valid(workplace):
		workplace.release_worker(ant)
	workplace = null

func capture_state(state: Dictionary, buildings: Array[Building]) -> void:
	state["workplace"] = buildings.find(workplace)
	state["_waiting_for_work"] = waiting_for_work
	state["_work_seconds"] = plan.work_seconds if plan != null else 0.0
	if plan != null:
		state["foodless"] = plan.foodless

func restore_state(state: Dictionary, buildings: Array[Building]) -> void:
	workplace = buildings[state.workplace] as Workplace if state.workplace >= 0 else null
	waiting_for_work = state._waiting_for_work
	if workplace == null:
		return
	workplace.reserve_worker(ant)
	if state.status == AntAgent.Status.WORKING:
		workplace.begin_work(ant)
	plan = WorkPlan.new()
	plan.workplace = workplace
	plan.foodless = state.get("foodless", false)
	plan.work_seconds = state.get("_work_seconds", ant._timer)
