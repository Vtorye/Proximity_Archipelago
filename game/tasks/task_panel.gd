class_name TaskPanel
extends PanelContainer
## Three compact requests. Availability uses the same atomic inventory rules as payment.
var director: TaskDirector
var _content: VBoxContainer
var _queued := false
func _ready() -> void:
	custom_minimum_size.x = 198
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 3)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 240
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	AppSettings.changed.connect(_queue_refresh)
	director.changed.connect(_queue_refresh)
	director.world.inventory.changed.connect(_queue_refresh)
	director.world.match_controller.time_changed.connect(func(_seconds: int): _queue_refresh())
	_refresh()
func _queue_refresh() -> void:
	if _queued: return
	_queued = true
	_refresh.call_deferred()
func _refresh() -> void:
	_queued = false
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.add_child(_label("Уровень %d · %d/%d" % [director.level, director.closed, director.stage().tasks.size()], ColonyStyle.ACCENT))
	for index in range(director.slots.size()):
		var task: TaskSpec = director.slots[index]
		if task == null: continue
		var title: Label = _label(task.title)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_content.add_child(title)
		var cost: Label = _label(BuildCostText.format(director.price(index)))
		cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cost.custom_minimum_size.x = 160 * AppSettings.ui_scale
		_content.add_child(cost)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		for cancel in [false, true]:
			var button: Button = ColonyStyle.button("Отказ" if cancel else "+%d c" % task.reward_seconds)
			if not cancel and not task.rewards.is_empty():
				button.text += " +%d" % BuildController.price_amount(task.rewards, task.rewards[0].type)
				button.icon = task.rewards[0].type.icon
				button.expand_icon = true
				button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				button.add_theme_constant_override("icon_max_width", 8)
			button.custom_minimum_size.y = 22 * AppSettings.ui_scale
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_override("font", ColonyStyle.SECONDARY_FONT)
			button.add_theme_font_size_override("font_size", 8)
			button.set_meta(&"cancel", cancel)
			button.set_meta(&"task_index", index)
			button.disabled = not director.can_pay(index, cancel)
			button.tooltip_text = "Отказ: %s. Без награды." % BuildCostText.format(director.price(index, true)) if cancel else "Сдать: %s. Награда: %s и %d с." % [BuildCostText.format(director.price(index)), BuildCostText.format(task.rewards), task.reward_seconds]
			button.pressed.connect(func(): director.submit(index, cancel))
			row.add_child(button)
		_content.add_child(row)
	var message: Label = _label(director.message, ColonyStyle.MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(message)
	var missing := 0
	var occupied := 0
	for ant in director.world.population.agents():
		if ant.status != AntAgent.Status.HOME: continue
		if ant.waiting_reason == WorkPlan.WaitReason.MISSING_INPUTS: missing += 1
		elif ant.waiting_reason == WorkPlan.WaitReason.SLOTS_FULL: occupied += 1
	if occupied > 0 or missing > 0:
		var waiting: Label = _label("Ждут мест: %d; сырья: %d" % [occupied, missing], ColonyStyle.MUTED)
		waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(waiting)

func _label(text: String, color: Color = ColonyStyle.TEXT) -> Label:
	var label: Label = ColonyStyle.label(text, 4, color)
	label.add_theme_font_override("font", ColonyStyle.SECONDARY_FONT)
	label.add_theme_font_size_override("font_size", 8)
	return label
