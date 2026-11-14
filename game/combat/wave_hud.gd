class_name WaveHud
extends PanelContainer
## A compact clock stays between the task list and the inspector.
var director: CombatDirector
@onready var _label: Label = %Clock

func _ready() -> void:
	director.changed.connect(refresh)
	refresh()

func refresh() -> void:
	var seconds: int = ceili(maxf(0, director.spawner.remaining))
	_label.text = tr("ui.waves.next") % [director.spawner.number + 1, seconds / 60, seconds % 60]
	_label.text += "\n" + tr("ui.waves.enemies") % director.spiders.size()
	_label.add_theme_color_override("font_color", ColonyStyle.DANGER if not director.spiders.is_empty() else ColonyStyle.ACCENT)
