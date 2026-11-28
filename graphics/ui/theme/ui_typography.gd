class_name UiTypography
extends Resource

## Minimum sizes offered to the player, in ascending order.
@export var minimum_sizes: Array[int]
## Index used when no text preference has been saved.
@export_range(0, 16) var default_index: int
@export_range(1, 128) var caption_size: int
@export_range(1, 128) var compact_button_size: int
@export_range(1, 128) var body_size: int
@export_range(1, 128) var heading_size: int
@export_group("Building Details")
@export_range(8, 24) var details_body_size := 12
@export_range(8, 28) var details_heading_size := 14
## Increase details more gently than the main interface at larger text settings.
@export_range(0, 4) var details_size_step := 1
