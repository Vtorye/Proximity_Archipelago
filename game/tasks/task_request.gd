class_name TaskRequest
extends PanelContainer
## A task's authored variants are separate cards, sharing one placement status.

signal order_requested(task_id: StringName, variant_id: StringName)
signal info_requested(option: BuildOption)

const CARD: PackedScene = preload("res://game/ui/construction_card.tscn")
const UNLOCK: Texture2D = preload("res://game/assets/ui/task_unlock.svg")
var _controller: BuildController
var _cards: Dictionary[ConstructionCard, TaskBuildOrder] = {}

func configure(director: TaskDirector, task: TaskSpec) -> void:
	_controller = director.world.build_controller
	%Title.text = task.title
	var unlocks := PackedStringArray()
	var unlock_row: RichTextLabel = %Unlocks
	var icon_size := unlock_row.get_theme_font_size(&"normal_font_size")
	for option in task.unlocks:
		if not _controller.options.has(option):
			if unlocks.is_empty():
				unlock_row.add_image(UNLOCK, icon_size, icon_size)
			unlocks.append(tr(option.display_name))
			var icon: Texture2D = director.world.art.build_icon(option)
			unlock_row.add_text(" ")
			if icon != null:
				unlock_row.add_image(icon, icon_size, icon_size)
	if not unlocks.is_empty():
		unlock_row.tooltip_text = tr("ui.task.unlocks") % ", ".join(unlocks)
		unlock_row.show()
	var placed := director.placed_order(task)
	if placed != null:
		var choice := placed.variant
		%Status.text = tr("ui.task.building_variant") % tr(choice.label if not choice.label.is_empty() else choice.building.display_name)
		%Status.show()
	for variant in task.variants:
		if variant == null or variant.building == null:
			continue
		var order := TaskBuildOrder.new(task, variant)
		var card: ConstructionCard = CARD.instantiate()
		%Offers.add_child(card)
		card.configure(variant.building, director.world.art)
		card.show_offer(order, _controller.price(variant.building))
		card.disabled = not director.can_place(order)
		var chosen := placed != null and placed.variant == variant
		card.toggle_mode = chosen
		card.set_pressed_no_signal(chosen)
		if placed != null and placed.variant != variant:
			card.modulate.a = 0.55
		card.pressed.connect(AppSettings.play_click)
		card.pressed.connect(order_requested.emit.bind(task.id, variant.id))
		card.info_requested.connect(info_requested.emit)
		_cards[card] = order

func refresh_prices() -> void:
	for card in _cards:
		card.set_price(_controller.price(card.option))

func refresh_availability(director: TaskDirector) -> void:
	for card in _cards:
		card.disabled = not director.can_place(_cards[card])
