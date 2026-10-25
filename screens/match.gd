extends Screen

## Manual check of the end-of-match overlay: enable in the Inspector and start the match.
@export var debug_show_result: bool = false
var _world: World
var _controller: MatchController
var _active := false

func _ready() -> void:
	_world = $SubViewportContainer/SubViewport/Wolrd1
	_controller = _world.match_controller
	_controller.completed.connect(_on_completed)

func on_focus() -> void:
	_active = true
	_world.start()

func on_blur() -> void:
	_active = false
	_world.stop()

func _on_completed(summary: MatchSummary) -> void:
	if not _active or Router.is_navigating():
		return
	if Router.push_overlay(&"match_result", summary) != null:
		PauseController.acquire(&"result")
