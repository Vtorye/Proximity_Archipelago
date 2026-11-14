extends MenuBase
## End-of-match summary. Cannot be dismissed with Esc: navigation starts a new session.
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	dismissable = false
	ColonyStyle.apply(self)
	var summary: MatchSummary = payload as MatchSummary
	var won: bool = summary != null and summary.won
	%Heading.text = "ui.result.victory" if won else "ui.result.defeat"
	if summary != null and summary.reason == &"colony_destroyed":
		%Reason.text = "ui.result.colony_destroyed"
	else:
		%Reason.text = "ui.result.goal_reached" if won else "ui.result.time_up"
	if summary != null:
		for entry in summary.resources:
			var line: Label = preload("res://game/ui/nest_stock_label.tscn").instantiate()
			line.text = tr("ui.colony.amount") % [tr(entry.type.display_name), entry.amount]
			%Resources.add_child(line)
		%TimeLeft.text = tr("ui.result.time_left") % [int(summary.time_left) / 60, int(summary.time_left) % 60]
		%TimeLeft.show()
		if summary.development_level > 0:
			%Level.text = tr("ui.result.level") % summary.development_level
			%Completed.text = tr("ui.result.task_counts") % [summary.tasks_completed, summary.tasks_skipped]
			%Level.show()
			%Completed.show()
	controls[&"again"] = %Again
	%Again.pressed.connect(AppSettings.play_click)
	%Again.pressed.connect(Router.restart_current)
	controls[&"main"] = %MainMenu
	%MainMenu.pressed.connect(AppSettings.play_click)
	%MainMenu.pressed.connect(_go_to_main_menu)
	default_focus = %Again

func _go_to_main_menu() -> void:
	# Explicitly unpause before navigating away through the owning pause boundary.
	Router.goto(&"main_menu")
