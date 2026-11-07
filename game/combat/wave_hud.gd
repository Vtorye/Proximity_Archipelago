class_name WaveHud
extends PanelContainer
## A compact clock stays between the task list and the inspector.
var director: CombatDirector
var _label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -76
	offset_right = 76
	offset_top = 64
	_label = ColonyStyle.label("", 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	director.changed.connect(refresh)
	tooltip_text = "ui.waves.hint"
	refresh()

func refresh() -> void:
	var seconds: int = ceili(maxf(0, director.spawner.remaining))
	_label.text = tr("ui.waves.next") % [director.spawner.number + 1, seconds / 60, seconds % 60]
	_label.text += "\n" + tr("ui.waves.enemies") % director.spiders.size()
	_label.add_theme_color_override("font_color", ColonyStyle.DANGER if not director.spiders.is_empty() else ColonyStyle.ACCENT)
