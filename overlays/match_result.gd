extends MenuBase
## End-of-match summary. Cannot be dismissed with Esc: navigation starts a new session.
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	dismissable = false
	var summary: MatchSummary = payload as MatchSummary
	var content: VBoxContainer = ColonyStyle.modal(self, 192)
	var won: bool = summary != null and summary.won
	content.add_child(ColonyStyle.label("Победа" if won else "Поражение", 12, ColonyStyle.ACCENT))
	content.add_child(ColonyStyle.label("Цель достигнута" if won else "Время вышло"))
	if summary != null:
		for entry in summary.resources:
			content.add_child(ColonyStyle.label("%s: %d" % [entry.type.display_name, entry.amount]))
		content.add_child(ColonyStyle.label("Осталось %02d:%02d" % [int(summary.time_left) / 60, int(summary.time_left) % 60], 8, ColonyStyle.MUTED))
	var again: Button = ColonyStyle.button("Новая игра", true)
	again.pressed.connect(func(): Router.goto(&"match"))
	content.add_child(again)
	controls[&"again"] = again
	var main: Button = ColonyStyle.button("В меню")
	main.pressed.connect(_go_to_main_menu)
	content.add_child(main)
	controls[&"main"] = main
	default_focus = again

func _go_to_main_menu() -> void:
	# Explicitly unpause before navigating away through the owning pause boundary.
	Router.goto(&"main_menu")
