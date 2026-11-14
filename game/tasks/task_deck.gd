class_name TaskDeck
extends Resource
@export var requests: Array[TaskSpec] = []
@export var stages: Array[TaskStage] = []
@export var choose_upgrades := false
@export var loop_last_stage := true
@export var unlocked_road: TileBuildOption
@export var replaced_road: TileBuildOption

func validate(stock: WorldInventory) -> Array[String]:
	var errors: Array[String] = []
	var prices := PriceService.new()
	if stages.is_empty(): errors.append(resource_path + ": empty stages")
	var ids: Dictionary[StringName, bool] = {}
	for request in requests:
		if request == null: errors.append(resource_path + ": missing request")
		else: _validate_request(request, stock, prices, ids, errors)
	for stage in stages:
		if stage == null or stage.tasks.is_empty():
			errors.append(resource_path + ": empty stage")
			continue
		if stage.upgrade == 0:
			if unlocked_road == null or replaced_road == null:
				errors.append(resource_path + ": road upgrade needs both road definitions")
			elif unlocked_road.id == replaced_road.id:
				errors.append(resource_path + ": upgraded road must replace a different option")
		if stage.upgrade not in [0, 1, 2] or stage.upgrade_factor <= 0 or not is_finite(stage.upgrade_factor): errors.append(resource_path + ": invalid upgrade")
		if stage.upgrade == 1 and stage.upgrade_factor > 1: errors.append(resource_path + ": discount factor must not exceed one")
		if stage.upgrade == 2 and stage.upgrade_factor < 1: errors.append(resource_path + ": speed upgrade must not slow ants")
		for task in stage.tasks:
			if task == null: errors.append(resource_path + ": missing task")
			elif not ids.has(task.id): _validate_request(task, stock, prices, ids, errors)
	prices.free()
	return errors

func _validate_request(task: TaskSpec, stock: WorldInventory, prices: PriceService, ids: Dictionary[StringName, bool], errors: Array[String]) -> void:
	if task.id == &"" or ids.has(task.id): errors.append(resource_path + ": duplicate or missing task ID")
	ids[task.id] = true
	if task.reward_seconds < 0 or not is_finite(task.reward_seconds): errors.append(resource_path + ": invalid time reward")
	if task.building == null or task.diversion == null: errors.append(resource_path + ": request needs building and diversion options")
	for option in [task.building, task.diversion]:
		if option != null:
			if option.id == &"" or not prices.valid(option): errors.append(resource_path + ": invalid request option")
			for cost in option.costs:
				if cost == null or not stock.is_registered(cost.type): errors.append(resource_path + ": unknown request cost resource")
	for reward in task.rewards:
		if reward == null or reward.type == null or not stock.is_registered(reward.type): errors.append(resource_path + ": invalid request reward")
	for option in task.unlocks:
		if option == null or option.id == &"" or not prices.valid(option): errors.append(resource_path + ": invalid building unlock")
		elif option is WorkplaceUpgradeOption and (not option.valid() or not stock.is_registered(option.source_type)): errors.append(resource_path + ": invalid resource facility")
