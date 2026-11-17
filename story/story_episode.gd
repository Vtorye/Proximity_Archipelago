extends Resource
class_name StoryEpisode
## Per-episode runtime configuration around a Dialogue Manager timeline.

@export var dialogue: DialogueResource
@export var opening_order: TaskSpec
@export var road_option: TileBuildOption
@export var road_cell: Vector2i
@export var order_cell: Vector2i
