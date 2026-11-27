class_name UiPresentation
extends Resource

@export var dock_clearance: float
@export_range(0.05, 0.2, 0.01) var task_strip_height_ratio := 0.2
@export var toast_duration: float
@export var low_food_threshold: int
@export var timer_warning_seconds: int
@export var ghost_hover_opacity: float
@export var ghost_opacity: float
@export var outline_inset: float
@export var outline_width: float
@export var removal_fill: Color
@export var navigation_refresh: float
@export var navigation_fallback_speed: float
@export var navigation_cell_brightness: float
@export var navigation_cell_opacity: float
@export var navigation_min_label_width: float
## Buildings and construction sites get labels at this camera zoom.
@export_range(0.25, 6.0, 0.05) var navigation_point_label_zoom := 1.0
@export var navigation_font_size: int
@export var navigation_baseline: float
@export var grid_color: Color
@export var grid_width: float
@export var selection_pulse_seconds: float
@export var selection_min_opacity: float
@export var selection_arm_pixels: float
@export var selection_max_arm: float

@export_group("Menu Backdrop")
@export var backdrop_tile_size: float
@export var backdrop_ant_count: int
@export var backdrop_ant_speed: float
@export var backdrop_ant_stride_frequency: float

@export_range(0.05, 1.0, 0.01) var backdrop_landmark_scale := 0.65
@export_range(0.05, 2.0, 0.01) var backdrop_ant_scale := 0.9
@export_range(0, 500) var backdrop_grain_count := 76
@export var backdrop_berries_position := Vector2(0.48, 0.18)
@export var backdrop_timber_position := Vector2(0.59, 0.28)
@export var backdrop_stone_position := Vector2(0.43, 0.82)
@export var backdrop_nest_position := Vector2(0.39, 0.31)
@export var backdrop_canteen_position := Vector2(0.57, 0.48)
@export_range(0.0, 2.0, 0.01) var backdrop_spider_speed_ratio := 0.6
@export_range(0.0, 1.0, 0.01) var backdrop_spider_start_phase := 0.68

@export_range(0, 50) var backdrop_ant_overhang := 8
@export_range(0.0, 50.0, 1.0) var backdrop_spider_overhang := 18.0
@export var backdrop_spider_lane_offset := Vector2(-8.0, -7.0)
@export var backdrop_spider_stride_frequencies := Vector2(9.0, 8.0)
@export var backdrop_lane_sway := Vector2(2.5, 2.5)

@export_group("Construction")
@export_range(0.05, 1.0, 0.01) var construction_palette_height_ratio := 1.0 / 6.0
@export_range(32.0, 1000.0, 1.0, "or_greater", "suffix:px") var construction_details_width := 400.0
@export_range(0.0, 1.0, 0.01) var inactive_offer_opacity := 0.55
