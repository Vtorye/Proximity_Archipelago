extends Control
## Standalone preview of the artist's mask-driven terrain shader.

@onready var map_view: SubViewport = $MapView
@onready var terrain_display: ColorRect = $TerrainDisplay

func _ready() -> void:
	var shader_material: ShaderMaterial = terrain_display.material as ShaderMaterial
	shader_material.set_shader_parameter("world_curr_col", map_view.get_texture())
