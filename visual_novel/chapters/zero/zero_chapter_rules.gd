class_name ZeroChapterRules
extends FirstChapterRules

@export_group("Lessons")
@export var wall: SceneBuildOption
@export var statue: SceneBuildOption
@export var statue_order: TaskSpec
@export var wall_cell: Vector2i
@export var demolition_wall_cells: Array[Vector2i] = []
@export var statue_cells: Array[Vector2i] = []
@export var timber_cell: Vector2i
@export var stone_cell: Vector2i
@export var finite_stone_cell: Vector2i
@export_range(1, 1000, 1) var quarry_target := 50
@export var quarry_roads: Array[Vector2i] = []
@export var depot_minimum := 4
@export var depot_maximum := 8

@export_group("Timed Objective")
@export_range(60, 1800, 1, "suffix:s") var preparation_seconds := 720
@export var preparation_stock: Array[ResourceAmount] = []
@export var protected_walls: Rect2i
@export var quarry_depot_cell: Vector2i
@export_range(0, 1000, 1) var quarry_depot_reserve := 64

@export_group("Finale")
@export var military_scene: PackedScene
@export var military_entry: Vector2i
@export var military_destination: Vector2i
@export var breach_cell: Vector2i
@export var spider_entry: Vector2i
@export_range(1, 128, 1, "suffix:px/s") var military_speed := 42.0
@export_range(1, 128, 1, "suffix:px/s") var approach_speed := 24.0
@export_range(0.1, 5.0, 0.1, "suffix:s") var breach_delay := 0.6
