class_name TaskPanel
extends PanelContainer
## Three compact royal requests with two construction routes each.
var director: TaskDirector
@onready var _requests: VBoxContainer = %Requests
var _queued := false
signal order_requested(index: int, diversion: bool)
@onready var _waiting: Label = %Waiting
func _ready() -> void:
	AppSettings.language_changed.connect(_queue_refresh)
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
		if not task.unlocks.is_empty():
			var names := PackedStringArray()
			for option in task.unlocks:
				if not director.world.build_controller.options.has(option): names.append(tr(option.display_name))
			if not names.is_empty():
				title.text += " · " + ", ".join(names)
				title.tooltip_text = tr("ui.task.unlocks") % ", ".join(names)
				title.add_theme_color_override("font_color", ColonyStyle.color(&"accent"))
		for diversion in [false, true]:
			var button: Button = request.get_node("Actions/Diversion" if diversion else "Actions/Build")
			var option: BuildOption = task.diversion if diversion else task.building
			var label_key: String = task.diversion_label if diversion else task.building_label

			if option != null:
				button.icon = director.world.art.build_icon(option)
				var label := tr(label_key if not label_key.is_empty() else option.display_name)
				var time := tr("ui.task.time_reward") % task.time_reward_for(diversion)
				button.tooltip_text = "%s\n%s\n%s" % [label, time, BuildCostText.format(task.resources_for(diversion))]
			else:
				button.hide()
			button.pressed.connect(AppSettings.play_click)
			button.set_meta(&"diversion", diversion)
			button.set_meta(&"task_index", index)
			button.disabled = option == null or director.active_order_id != &""
			button.pressed.connect(order_requested.emit.bind(index, diversion))
		_requests.add_child(request)
	%Message.text = director.display_message()
	_update_availability()

func _update_availability() -> void:
	if _requests == null: return
	for button in _requests.find_children("*", "Button", true, false):
		var task: TaskSpec = director.slots[button.get_meta(&"task_index")]
		var option: BuildOption
		if task != null:
			option = task.diversion if button.get_meta(&"diversion") else task.building
		button.disabled = option == null or director.active_order_id != &"" or director.pending_reward
	var missing := 0
	var occupied := 0
	for ant in director.world.population.agents():
		if ant.status != AntAgent.Status.HOME: continue
		if ant.waiting_reason == WorkPlan.WaitReason.MISSING_INPUTS: missing += 1
		elif ant.waiting_reason == WorkPlan.WaitReason.SLOTS_FULL: occupied += 1
	if is_instance_valid(_waiting):
		_waiting.text = tr("ui.task.waiting") % [occupied, missing]
		_waiting.visible = occupied > 0 or missing > 0
