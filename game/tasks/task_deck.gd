class_name TaskDeck
extends Resource
@export var stages: Array[TaskStage] = []
@export_range(0.0, 1.0) var cancellation_fraction := 0.3333333333
@export var loop_last_stage := true
@export var repeat_cost_multiplier := 1.25
@export var unlocked_road: BuildOption

func validate(stock: WorldInventory) -> Array[String]:
	var errors: Array[String] = []
	if stages.is_empty(): errors.append(resource_path + ": empty stages")
	if cancellation_fraction < 0 or cancellation_fraction > 1 or repeat_cost_multiplier < 1 or not is_finite(repeat_cost_multiplier): errors.append(resource_path + ": invalid cancellation or difficulty factor")
	var ids: Dictionary[StringName, bool] = {}
	for stage in stages:
		if stage == null or stage.tasks.is_empty():
			errors.append(resource_path + ": empty stage")
			continue
		if stage.upgrade == 0 and unlocked_road == null: errors.append(resource_path + ": road upgrade has no road definition")
		if stage.upgrade not in [0, 1, 2] or stage.upgrade_factor <= 0 or not is_finite(stage.upgrade_factor): errors.append(resource_path + ": invalid upgrade")
		if stage.upgrade == 1 and stage.upgrade_factor > 1: errors.append(resource_path + ": discount factor must not exceed one")
		if stage.upgrade == 2 and stage.upgrade_factor < 1: errors.append(resource_path + ": speed upgrade must not slow ants")
		for task in stage.tasks:
			if task == null:
				errors.append(resource_path + ": missing task")
				continue
			if task.id == &"" or ids.has(task.id): errors.append(resource_path + ": duplicate or missing task ID")
			ids[task.id] = true
			if task.reward_seconds < 0 or not is_finite(task.reward_seconds): errors.append(resource_path + ": invalid time reward")
			for entry in task.costs + task.rewards + task.cancellation_costs:
				if entry == null or entry.amount < 0 or entry.type == null or not stock.is_registered(entry.type): errors.append(resource_path + ": invalid task resource")
	return errors
