class_name ConstructionService
extends Node
## Orders reserve space immediately; carriers deliver crates and workers assemble buildings.
signal changed
var controller: BuildController
var art: ArtCatalog
var sites: Array[ConstructionSite] = []
var _servicing := false

func _ready() -> void:
	controller.registry.removed.connect(_source_removed)

func _source_removed(building: Building) -> void:
	if building is House:
		for site in sites: site.crates.erase(building)
	elif building is Workplace:
		for site in sites.duplicate():
			if site.option is WorkplaceUpgradeOption and site.cell == building.cell: controller._remove_site(site)

static func needs_builders(option: BuildOption, quote: Array[ResourceAmount]) -> bool:
	# Any crown-funded purchase is commissioned instantly, including mixed prices.
	for item in quote:
		if item != null and item.type != null and item.type.id == &"royal" and item.amount > 0: return false
	return option != null

func at(cell: Vector2i, terrain: bool = false) -> ConstructionSite:
	for site in sites:
		if site.active and (site.option is TileBuildOption) == terrain and site.footprint().has(cell): return site
	return null

func enqueue(command: BuildCommand, candidate: Building, quote: Array[ResourceAmount], crates: Dictionary) -> ConstructionSite:
	var site := ConstructionSite.new()
	site.service = self
	site.candidate = candidate
	site.required = _aggregate(quote)
	site.crates = crates
	site.setup(command.cell, command.option)
	site.position = controller.buildings.to_local(controller.route_service.cell_to_world(command.cell))
	sites.append(site)
	controller.buildings.add_child(site)
	if command.option is SceneBuildOption: controller.registry.register(site)
	if controller.prices != null: controller.prices.queue_order(command.option, 1)
	changed.emit()
	return site

func claim(ant: AntAgent) -> ConstructionJob:
	if _servicing: return null
	_servicing = true
	var best: ConstructionJob
	var lowest := INF
	var cell: Vector2i = controller.route_service.world_to_cell(ant.global_position)
	for site in sites:
		if not site.active: continue
		_replenish(site)
		var delivery: Route = site.route(cell)
		if not delivery.is_valid(): continue
		if site.supplied():
			if ant.role != AntAgent.Role.WORKER or is_instance_valid(site.builder): continue
			var energy: float = ant.planner.travel_energy(delivery.cost, ant.speed) + (site.option.construction_seconds - site.progress) * AntNeeds.WORK_RATE
			if not ant._is_foodless(): energy += ant.planner.escape_energy(delivery.cells.back(), ant.speed)
			if not ant.needs.can_afford(energy) or delivery.cost >= lowest: continue
			best = ConstructionJob.new()
			best.site = site
			best.assembly = true
			lowest = delivery.cost
		else:
			for source: House in site.crates:
				if not is_instance_valid(source) or not source.is_inside_tree() or site.crates[source].is_empty(): continue
				var pickup: Route = controller.logistics.route_to(source, cell)
				if not pickup.is_valid():
					continue
				var outward: Route = site.route(pickup.cells.back())
				if not ant._can_start_pickup(pickup, outward):
					continue
				var cost: float = pickup.cost + outward.cost
				if cost >= lowest: continue
				best = ConstructionJob.new()
				best.site = site
				best.source = source
				lowest = cost
	if best != null:
		if best.assembly:
			best.site.builder = ant
		else:
			var limit: int = ant.carry_capacity
			var crate: Array = best.site.crates[best.source]
			for item: ResourceAmount in crate:
				var count: int = mini(limit, item.amount)
				if count <= 0: continue
				best.materials.append(_item(item.type, count))
				item.amount -= count
				best.site.transit[item.type.id] = best.site.transit.get(item.type.id, 0) + count
				limit -= count
			best.site.crates[best.source] = crate.filter(func(item: ResourceAmount) -> bool: return item.amount > 0)
	_servicing = false
	return best

func deliver(job: ConstructionJob) -> bool:
	if not job.live() or not job.picked_up: return false
	for item in job.materials:
		job.site.transit[item.type.id] -= item.amount
		job.site.delivered[item.type.id] = job.site.delivered.get(item.type.id, 0) + item.amount
	job.materials.clear()
	job.site.queue_redraw()
	changed.emit()
	return true

func release(job: ConstructionJob) -> void:
	if job == null: return
	if job.live():
		if job.assembly:
			job.site.builder = null
		else:
			for item in job.materials: job.site.transit[item.type.id] -= item.amount
			if not job.picked_up and is_instance_valid(job.source) and job.source.is_inside_tree():
				if not job.site.crates.has(job.source): job.site.crates[job.source] = []
				job.site.crates[job.source].append_array(job.materials)
	elif not job.picked_up and not job.materials.is_empty():
		_refund(job.source, job.materials)
	job.materials.clear()
	changed.emit()

func assemble(job: ConstructionJob, delta: float) -> bool:
	if not job.live() or not job.assembly or not job.site.supplied(): return false
	var site: ConstructionSite = job.site
	site.progress = minf(site.option.construction_seconds, site.progress + delta)
	site.queue_redraw()
	if site.progress >= site.option.construction_seconds:
		return controller.finish_construction(site)
	return false

## Completion rechecks today's navigation and occupants, not the placement-time snapshot.
func complete(site: ConstructionSite) -> bool:
	if controller._committing or not site.active: return false
	var command := BuildCommand.create(site.cell, site.option)
	var candidates: Array[Building] = []
	if is_instance_valid(site.candidate): candidates.append(site.candidate)
	if site.option is WorkplaceUpgradeOption:
		var source := controller.registry.at(site.cell) as Workplace
		if source == null or not source.accepts_improvement(site.option):
			controller._remove_site(site)
			return true
	if controller.terrain != null and not (site.option is SceneBuildOption and site.option.requires_water) and not controller.terrain.allows(site.option, site.cell):
		controller._remove_site(site)
		return true
	if not controller._safety().preserves_escape([command], candidates): return false
	controller._committing = true
	var option: BuildOption = site.option
	var cell: Vector2i = site.cell
	if option is TileBuildOption:
		controller.apply_surface(option, cell)
	elif option is WorkplaceUpgradeOption:
		(controller.registry.at(cell) as Workplace).install_improvement(option)
	var candidate: Building = site.candidate
	site.candidate = null
	finished(site)
	var cells: Array[Vector2i] = site.footprint()
	site.demolish()
	site.queue_free()
	if candidate != null:
		var blocked: Array[Vector2i] = controller.registry.blocked_cells()
		if candidate.option.blocks_movement: blocked.append_array(candidate.footprint())
		controller.route_service.update_cells(cells, blocked)
		candidate.position = controller.buildings.to_local(controller.route_service.cell_to_world(cell))
		controller.buildings.add_child(candidate)
		controller.registry.register(candidate)
	else:
		controller.route_service.update_cells(cells, controller.registry.blocked_cells())
	controller._committing = false
	if controller.prices != null: controller.prices.record(GameEvents.Kind.TERRAIN_CHANGED if option is TileBuildOption else GameEvents.Kind.BUILDING_BUILT, option.id)
	controller.built.emit(option, cell)
	controller.population.planner._queue_workplace_refresh()
	controller.changed.emit()
	return true

func cancel(site: ConstructionSite) -> void:
	if not site.active: return
	site.active = false
	sites.erase(site)
	for source: House in site.crates: _refund(source, site.crates[source])
	site.crates.clear()
	if controller.prices != null: controller.prices.queue_order(site.option, -1)
	changed.emit()

func finished(site: ConstructionSite) -> void:
	site.active = false
	sites.erase(site)
	if controller.prices != null: controller.prices.queue_order(site.option, -1)
	changed.emit()

func _replenish(site: ConstructionSite) -> void:
	# A killed courier loses its load. Replacement materials must be paid for again.
	var missing: Array[ResourceAmount] = []
	for required in site.required:
		var accounted: int = site.delivered.get(required.type.id, 0) + site.transit.get(required.type.id, 0)
		for source: House in site.crates:
			if not is_instance_valid(source) or not source.is_inside_tree(): continue
			for item: ResourceAmount in site.crates[source]:
				if item.type.id == required.type.id: accounted += item.amount
		if accounted < required.amount: missing.append(_item(required.type, required.amount - accounted))
	if missing.is_empty() or not controller.inventory.can_afford_all(missing, true, true):
		return
	var sources: Array[House] = controller.logistics.construction_sources(site.entry_cells())
	var primary: House = controller.logistics.main_nest
	var replacements: Variant = controller.inventory.allocate_build_materials(missing, primary, sources, {})
	if replacements == null:
		return
	controller.inventory.debit_build_materials(replacements, primary)
	for source: House in replacements:
		if not site.crates.has(source): site.crates[source] = []
		site.crates[source].append_array(replacements[source])

func _refund(source, materials: Array) -> void:
	var cargo: Array[ResourceAmount] = []
	cargo.assign(materials)
	if not is_instance_valid(source) or not controller.logistics.owns(source): return
	controller.inventory.deposit(null if source == controller.logistics.main_nest else source, cargo)

static func _item(type: ResourceType, count: int) -> ResourceAmount:
	var item := ResourceAmount.new()
	item.type = type
	item.amount = count
	return item

static func _aggregate(entries: Array[ResourceAmount]) -> Array[ResourceAmount]:
	var totals: Dictionary[StringName, ResourceAmount] = {}
	for item in entries:
		if not totals.has(item.type.id): totals[item.type.id] = _item(item.type, 0)
		totals[item.type.id].amount += item.amount
	var result: Array[ResourceAmount] = []
	result.assign(totals.values())
	return result
