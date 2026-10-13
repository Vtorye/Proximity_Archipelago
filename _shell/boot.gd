extends Node

@export
var manifest : Manifest

func _ready() -> void:
	Router.boot(manifest, %ScreenLayer, %MenuStack, %Fade)
	Router.init()
