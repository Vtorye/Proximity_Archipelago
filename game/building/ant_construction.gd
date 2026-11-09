class_name AntConstruction
extends RefCounted
## Construction execution is separate from production, hunger, and warehouse transfers.
var ant: AntAgent
var service: ConstructionService
var job: ConstructionJob

func decide() -> bool:
	if job != null:
		if resume(): return true
		release()
	job = service.claim(ant)
	if job == null: return false
	ant._release_work()
	ant._waiting_for_work = false
	ant._set_waiting_reason(WorkPlan.WaitReason.NONE)
	if resume():
		return true
	release()
	return false

func has_cargo() -> bool:
	return job != null and job.picked_up and not job.materials.is_empty()

func resume() -> bool:
	if job == null: return false
	var cell: Vector2i = ant.route_service.world_to_cell(ant.global_position)
	if not job.live():
		if has_cargo():
			# Cancelled orders send carried materials back through normal physical delivery.
			ant.cargo.assign(job.materials)
			job.materials.clear()
			job = null
			ant._deliver()
			return true
		return false
	var route: Route
	var destination: StringName
	if job.assembly:
		route = job.site.route(cell)
		destination = &"site_assembly"
	elif job.picked_up:
		route = job.site.route(cell)
		destination = &"site_delivery"
	else:
		route = service.pickup_route(job.source, cell)
		destination = &"site_pickup"
	if not route.is_valid(): return false
	var energy: float = ant.planner.travel_energy(route.cost, ant.speed * (TripPlanner.CARRY_SPEED_RATIO if has_cargo() else 1.0))
	if not ant._is_foodless(): energy += ant.planner.escape_energy(route.cells.back(), ant.speed)
	if not ant.needs.can_afford(energy):
		if has_cargo():
			ant._seek_food()
			return true
		return false
	ant._carrying = has_cargo()
	ant._walk(route, destination)
	return true

func arrive(destination: StringName) -> void:
	if job == null or not job.live():
		ant._decide()
		return
	match destination:
		&"site_pickup":
			if not is_instance_valid(job.source) or not service.controller.logistics.owns(job.source):
				release()
				ant._decide()
				return
			job.picked_up = true
			if not resume():
				ant._set_status(AntAgent.Status.WAITING_FOR_FOOD)
				ant._timer = 1.0
		&"site_delivery":
			service.deliver(job)
			job = null
			ant._carrying = false
			ant._decide()
		&"site_assembly":
			ant._set_status(AntAgent.Status.CONSTRUCTING)

func tick(delta: float) -> void:
	if job == null or not job.live():
		release()
		ant._decide()
		return
	var cell: Vector2i = ant.route_service.world_to_cell(ant.global_position)
	if not ant._is_foodless() and not ant.needs.can_afford(ant.planner.escape_energy(cell, ant.speed) + 1.0):
		release()
		ant._seek_food()
		return
	if service.assemble(job, delta):
		job = null
		ant._decide()

func release() -> void:
	if job != null and is_instance_valid(service): service.release(job)
	job = null
