extends Node

@export
var manifest : Manifest

func _ready() -> void:
	if not Router.boot(manifest, %ScreenLayer, %MenuStack, %Fade):
		push_error("Boot: shell configuration failed")
