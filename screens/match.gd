extends Screen

## Manual check of the end-of-match overlay: enable in the Inspector and start the match.
@export var debug_show_result: bool = false


func _ready() -> void:
	print("Match loaded with payload: ", payload)
	if debug_show_result:
		Router.push_overlay(&"match_result", {
			"result": "WIN",
			"reason": "Test: all goals reached",
			"resources": {"Wood": 12, "Food": 5},
			"time_left": 83.0,
		})
