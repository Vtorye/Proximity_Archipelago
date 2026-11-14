class_name TaskPanel
extends PanelContainer
## Three compact requests. Availability uses the same atomic inventory rules as payment.
var director: TaskDirector
@onready var _requests: VBoxContainer = %Requests
var _queued := false
@onready var _waiting: Label = %Waiting
func _ready() -> void:
	AppSettings.changed.connect(_queue_refresh)
	director.changed.connect(_queue_refresh)
	director.world.inventory.changed.connect(_update_availability)
	director.world.match_controller.time_changed.connect(func(_seconds: int): _update_availability())
	_refresh()
func _queue_refresh() -> void:
	if _queued: return
	_queued = true
	_refresh.call_deferred()
func _refresh() -> void:
	_queued = false
	for child in _requests.get_children():
		_requests.remove_child(child)
		child.queue_free()
	%Heading.text = tr("ui.task.level_progress") % [director.level, director.closed, director.stage().tasks.size()]
	for index in range(director.slots.size()):
		var task: TaskSpec = director.slots[index]
		if task == null: continue
		var request: VBoxContainer = preload("res://game/tasks/task_request.tscn").instantiate()
		var title: Label = request.get_node("Title")
		title.text = task.title
		var cost: Label = request.get_node("Cost")
		cost.text = BuildCostText.format(director.price(index))
		if not task.unlocks.is_empty():
			var names := PackedStringArray()
			for option in task.unlocks:
				if not director.world.build_controller.options.has(option): names.append(tr(option.display_name))
			if not names.is_empty():
				title.text += " · " + ", ".join(names)
				title.tooltip_text = tr("ui.task.unlocks") % ", ".join(names)
				title.add_theme_color_override("font_color", ColonyStyle.color(&"accent"))
		for cancel in [false, true]:
			var button: Button = request.get_node("Actions/Cancel" if cancel else "Actions/Submit")
			if not cancel:
				button.text = tr("ui.task.time_reward_short") % task.reward_seconds
			button.pressed.connect(AppSettings.play_click)
			if not cancel and not task.rewards.is_empty():
				button.text += " +%d" % BuildController.price_amount(task.rewards, task.rewards[0].type)
				button.icon = task.rewards[0].type.icon
				button.expand_icon = true
				button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				button.add_theme_constant_override("icon_max_width", 8)
			button.set_meta(&"cancel", cancel)
			button.set_meta(&"task_index", index)
			button.disabled = not director.can_pay(index, cancel)
			button.tooltip_text = tr("ui.task.cancel_hint") % BuildCostText.format(director.price(index, true)) if cancel else tr("ui.task.submit_hint") % [BuildCostText.format(director.price(index)), BuildCostText.format(task.rewards), task.reward_seconds]
			button.pressed.connect(func(): director.submit(index, cancel))
		_requests.add_child(request)
	%Message.text = director.display_message()
	_update_availability()

func _update_availability() -> void:
	if _requests == null: return
	for button in _requests.find_children("*", "Button", true, false):
		button.disabled = not director.can_pay(button.get_meta(&"task_index"), button.get_meta(&"cancel"))
	var missing := 0
	var occupied := 0
	for ant in director.world.population.agents():
		if ant.status != AntAgent.Status.HOME: continue
		if ant.waiting_reason == WorkPlan.WaitReason.MISSING_INPUTS: missing += 1
		elif ant.waiting_reason == WorkPlan.WaitReason.SLOTS_FULL: occupied += 1
	if is_instance_valid(_waiting):
		_waiting.text = tr("ui.task.waiting") % [occupied, missing]
		_waiting.visible = occupied > 0 or missing > 0
