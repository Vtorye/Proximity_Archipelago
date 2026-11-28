@tool
extends PanelContainer


func _ready() -> void:
	resized.connect(_update_paper_size)
	_update_paper_size()


func _update_paper_size() -> void:
	set_instance_shader_parameter(&"panel_size", size)
