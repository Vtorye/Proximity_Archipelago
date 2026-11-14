class_name CampaignPanel
extends Control
## Pauses the session while the player chooses a reward or destination.

const REWARD_NAMES: Array[String] = ["ui.voyage.road", "ui.voyage.discount", "ui.voyage.speed", "ui.voyage.satiety"]
const REWARD_DETAILS: Array[String] = ["ui.voyage.road_detail", "ui.voyage.discount_detail", "ui.voyage.speed_detail", "ui.voyage.satiety_detail"]
const DESTINATION_NAMES: Array[String] = ["ui.voyage.fertile_short", "ui.voyage.dry_short", "ui.voyage.rocky_short"]
const DESTINATION_DETAILS: Array[String] = ["ui.voyage.fertile_island", "ui.voyage.dry_island", "ui.voyage.rocky_island"]

var world: World
var controls: Array[Button] = []
var _signature := ""

@onready var _rewards: Array[Button] = [%Reward1, %Reward2, %Reward3]
@onready var _reward_details: Array[Label] = [%RewardDetail1, %RewardDetail2, %RewardDetail3]
@onready var _destinations: Array[Button] = [%Destination1, %Destination2, %Destination3]

func configure(session: World) -> void:
	world = session
	ColonyStyle.apply(self)
	for index in range(_rewards.size()):
		_rewards[index].pressed.connect(AppSettings.play_click)
		_rewards[index].pressed.connect(_choose_reward.bind(index))
		_destinations[index].pressed.connect(AppSettings.play_click)
		_destinations[index].pressed.connect(_travel.bind(index))
	%MainMenu.pressed.connect(AppSettings.play_click)
	%MainMenu.pressed.connect(func(): Router.goto(&"main_menu"))

func _process(_delta: float) -> void:
	var reward: bool = world.tasks != null and world.tasks.pending_reward
	var victory: bool = world.voyage != null and world.voyage.departed
	var signature := "%s/%s/%s" % [reward, victory, TranslationServer.get_locale()]
	if signature == _signature:
		return
	_signature = signature
	visible = reward or victory
	if not visible:
		return
	PauseController.acquire(&"voyage_choice")
	%Reward.visible = not victory
	%Departure.visible = victory
	if victory:
		_show_destinations()
	else:
		_show_rewards()
	controls[0].grab_focus()

func _show_rewards() -> void:
	%RewardHeading.text = tr("ui.voyage.level_complete") % world.tasks.level
	%RewardPrompt.text = "ui.voyage.choose_reward"
	var choices: Array[int] = world.tasks.reward_choices()
	for index in range(_rewards.size()):
		_rewards[index].text = REWARD_NAMES[choices[index]]
		_reward_details[index].text = REWARD_DETAILS[choices[index]]
	controls.assign(_rewards)

func _choose_reward(index: int) -> void:
	if world.tasks.choose_reward(index):
		SessionSave.write(world)
		hide()
		PauseController.release(&"voyage_choice")

func _show_destinations() -> void:
	SessionSave.write(world)
	%DepartureHeading.text = "ui.voyage.departure"
	%Score.text = tr("ui.voyage.score") % world.voyage.score
	%NextIsland.text = tr("ui.voyage.next_island") % (world.voyage.island + 1)
	%CarryOver.text = "ui.voyage.carry_over"
	%MainMenu.text = "ui.common.main_menu"
	for index in range(_destinations.size()):
		var layout: LevelData = world.voyage.destination_data(index)
		var button: Button = _destinations[index]
		button.text = DESTINATION_NAMES[index]
		button.tooltip_text = DESTINATION_DETAILS[index]
		button.icon = MapPreview.texture(layout, world.map.tile_set)
		button.disabled = layout == null
	controls.assign(_destinations)
	controls.append(%MainMenu)

func _travel(index: int) -> void:
	var selected: Dictionary = world.voyage.travel(index)
	if not selected.is_empty():
		Router.goto(&"match", selected)
