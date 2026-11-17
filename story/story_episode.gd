extends Resource
class_name StoryEpisode
## Per-episode runtime configuration around a Dialogue Manager timeline.

@export var episode_id: StringName = &""
@export var dialogue: DialogueResource
@export var pause_simulation := true
