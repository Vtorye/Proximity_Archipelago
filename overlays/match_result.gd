extends MenuBase
## End-of-match summary. Cannot be dismissed with Esc: the only exit is the main menu button.
##
## payload (Dictionary):
##   result:     "WIN" or "LOSS"
##   reason:     String, shown under the title
##   resources:  Dictionary of display name (String) -> amount (int), current stock
##   time_left:  float seconds remaining in the match

const MAIN_MENU_KEY := &"main_menu"

@onready var _title: Label = $CenterContainer/PanelContainer/VBoxContainer/TitleLabel
@onready var _reason: Label = $CenterContainer/PanelContainer/VBoxContainer/ReasonLabel
@onready var _resources: Label = $CenterContainer/PanelContainer/VBoxContainer/ResourcesLabel
@onready var _time: Label = $CenterContainer/PanelContainer/VBoxContainer/TimeLabel
@onready var _to_menu: Button = $CenterContainer/PanelContainer/VBoxContainer/MainMenuButton


func _ready() -> void:
	dismissable = false
	var summary: MatchSummary = payload as MatchSummary
	if summary == null:
		_reason.text = "Не удалось получить результат матча"
		return
	_title.text = "Победа" if summary.won else "Поражение"
	_reason.text = "Все цели достигнуты" if summary.won else "Время вышло"
	var parts: PackedStringArray = []
	for entry in summary.resources:
		parts.append("%s: %d" % [entry.type.display_name, entry.amount])
	_resources.text = "Запасы: " + ", ".join(parts)
	_time.text = "Оставшееся время: %s" % _format_time(summary.time_left)
	_to_menu.pressed.connect(_go_to_main_menu)
	default_focus = _to_menu


func _format_resources(resources: Variant) -> String:
	if not resources is Dictionary or (resources as Dictionary).is_empty():
		return "Запасы: нет данных"
	var parts: PackedStringArray = []
	for key in resources:
		parts.append("%s: %s" % [key, str(resources[key])])
	return "Запасы: " + ", ".join(parts)


func _format_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _go_to_main_menu() -> void:
	# Explicitly unpause before navigating away, as in pause_menu.gd
	Router.goto(MAIN_MENU_KEY)
