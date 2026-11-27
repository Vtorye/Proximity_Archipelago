class_name StoryCharacter
extends Resource

@export var id: StringName
@export var display_name: String
@export var portrait: Texture2D
@export_range(10.0, 150.0, 1.0) var characters_per_second := 45.0
@export_range(0.5, 2.0, 0.01) var voice_pitch := 1.0
@export var topic: StringName

