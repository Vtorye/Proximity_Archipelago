class_name CampaignPanel
extends Control
## One focused decision at a time; simulation is paused until a reward or destination is chosen.
var world: World
var controls: Array[Button] = []
var _signature := ""
var _content: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ColonyStyle.fill(self)
	_content = ColonyStyle.modal(self, 208)
	hide()

func _process(_delta: float) -> void:
	var reward: bool = world.tasks != null and world.tasks.pending_reward
	var victory: bool = world.voyage != null and world.voyage.departed
	var signature := "%s/%s/%s" % [reward, victory, TranslationServer.get_locale()]
	if signature == _signature: return
	_signature = signature
	visible = reward or victory
	if not visible: return
	PauseController.acquire(&"voyage_choice")
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	controls.clear()
	if victory: _victory()
	else: _reward()
	if not controls.is_empty(): controls[0].grab_focus()

func _text(value: String, color := ColonyStyle.TEXT, heading := false) -> void:
	var label: Label = ColonyStyle.label(value, 8 if heading else 4, color)
	if not heading: label.add_theme_font_override("font", ColonyStyle.SECONDARY_FONT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 200 * AppSettings.ui_scale
	_content.add_child(label)

func _action(title: String, action: Callable) -> void:
	var button: Button = ColonyStyle.button(title)
	button.custom_minimum_size.y = 28 * AppSettings.ui_scale
	button.add_theme_font_override("font", ColonyStyle.SECONDARY_FONT)
	button.add_theme_font_size_override("font_size", 8)
	button.pressed.connect(action)
	_content.add_child(button)
	controls.append(button)

func _reward() -> void:
	_text(tr("ui.voyage.level_complete") % world.tasks.level, ColonyStyle.ACCENT, true)
	_text(tr("ui.voyage.choose_reward"), ColonyStyle.MUTED)
	var titles := ["ui.voyage.road", "ui.voyage.discount", "ui.voyage.speed", "ui.voyage.satiety"]
	var descriptions := ["ui.voyage.road_detail", "ui.voyage.discount_detail", "ui.voyage.speed_detail", "ui.voyage.satiety_detail"]
	var choices: Array[int] = world.tasks.reward_choices()
	for index in range(3):
		_action(tr(titles[choices[index]]), func():
			if world.tasks.choose_reward(index):
				SessionSave.write(world)
				hide()
				PauseController.release(&"voyage_choice"))
		_text(tr(descriptions[choices[index]]), ColonyStyle.MUTED)

func _victory() -> void:
	SessionSave.write(world)
	_text(tr("ui.voyage.departure"), ColonyStyle.ACCENT, true)
	_text(tr("ui.voyage.score") % world.voyage.score)
	_text(tr("ui.voyage.next_island") % (world.voyage.island + 1), ColonyStyle.MUTED)
	for index in range(3):
		_action(tr(["ui.voyage.fertile_island", "ui.voyage.dry_island", "ui.voyage.rocky_island"][index]), func():
			var layout: Dictionary = world.voyage.travel(index)
			if not layout.is_empty(): Router.goto(&"match", layout))
	_text(tr("ui.voyage.carry_over"), ColonyStyle.MUTED)
	_action(tr("ui.common.main_menu"), func(): Router.goto(&"main_menu"))
