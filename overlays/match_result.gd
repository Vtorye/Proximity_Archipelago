extends MenuBase
## End-of-match summary. Cannot be dismissed with Esc: navigation starts a new session.
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	dismissable = false
	var summary: MatchSummary = payload as MatchSummary
	var content: VBoxContainer = ColonyStyle.modal(self, 192)
	var won: bool = summary != null and summary.won
	content.add_child(ColonyStyle.label("ui.result.victory" if won else "ui.result.defeat", 12, ColonyStyle.ACCENT))
	content.add_child(ColonyStyle.label("ui.result.goal_reached" if won else "ui.result.time_up"))
	if summary != null:
		for entry in summary.resources:
			content.add_child(ColonyStyle.label("%s: %d" % [tr(entry.type.display_name), entry.amount]))
		content.add_child(ColonyStyle.label(tr("ui.result.time_left") % [int(summary.time_left) / 60, int(summary.time_left) % 60], 8, ColonyStyle.MUTED))
	if summary != null and summary.development_level > 0:
		content.add_child(ColonyStyle.label("Уровень: %d" % summary.development_level))
		content.add_child(ColonyStyle.label("Выполнено: %d · отказов: %d" % [summary.tasks_completed, summary.tasks_skipped]))
	var again: Button = ColonyStyle.button("ui.result.new_game", true)
	again.pressed.connect(Router.restart_current)
	content.add_child(again)
	controls[&"again"] = again
	var main: Button = ColonyStyle.button("ui.common.main_menu")
	main.pressed.connect(_go_to_main_menu)
	content.add_child(main)
	controls[&"main"] = main
	default_focus = again

func _go_to_main_menu() -> void:
	# Explicitly unpause before navigating away through the owning pause boundary.
	Router.goto(&"main_menu")
