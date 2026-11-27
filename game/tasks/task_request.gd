class_name TaskRequest
extends PanelContainer
## A task's authored variants are separate cards, sharing one placement status.

signal order_requested(task_id: StringName, variant_id: StringName)
signal info_requested(option: BuildOption)

const OFFER: PackedScene = preload("res://game/tasks/task_offer.tscn")
var task: TaskSpec
var _controller: BuildController
var _offers: Array[TaskOffer] = []
var _placed: TaskBuildOrder

func configure(director: TaskDirector, definition: TaskSpec, number: int) -> void:
	task = definition
	_controller = director.world.build_controller
	%Title.text = tr(task.title) if task.build_count > 1 else tr("ui.task.numbered_title") % [director.level, number]
	_placed = director.placed_order(task)
	for variant in task.variants:
		if variant == null or variant.building == null:
			continue
		var offer: TaskOffer = OFFER.instantiate()
		%Offers.add_child(offer)
		offer.configure(TaskBuildOrder.new(task, variant), director.world.art)
		offer.refresh_price(_controller)
		offer.set_available(director.can_place(offer.order))
		if _placed != null:
			if _placed.variant == variant:
				offer.placement.tooltip_text = tr("ui.task.building_variant") % tr(offer.placement.tooltip_text)
			else:
				offer.modulate.a = 0.55
		offer.order_requested.connect(order_requested.emit)
		offer.info_requested.connect(info_requested.emit)
		_offers.append(offer)

func set_selection(selection: TaskBuildOrder) -> void:
	var selected := _placed if _placed != null else selection
	for offer in _offers:
		offer.set_selected(selected != null and selected.task == task and selected.variant == offer.order.variant)

func refresh_prices(pending: Dictionary[String, int] = {}) -> void:
	for offer in _offers:
		offer.refresh_price(_controller, pending)

func refresh_availability(director: TaskDirector) -> void:
	for offer in _offers:
		offer.set_available(director.can_place(offer.order))
