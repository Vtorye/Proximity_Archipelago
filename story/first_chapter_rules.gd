class_name FirstChapterRules
extends Resource

@export var dialogue: DialogueResource
@export var characters: Array[StoryCharacter] = []
@export var wishes: Array[BuildOption] = []
@export var road: TileBuildOption
@export var opening_order: TaskSpec
@export var followup_order: TaskSpec
@export var road_cell := Vector2i(26, 26)
@export var order_cell := Vector2i(26, 25)
@export var followup_cell := Vector2i(27, 24)
@export_range(8.0, 160.0, 1.0) var camera_pan_distance := 32.0
## Leave the guided cell between the stock summary and the task hint.
@export var camera_focus_ratio := Vector2(0.3, 0.56)
@export var delivery: ResourceAmount
@export var delivery_cell := Vector2i(18, 25)
@export var ground: TileBuildOption
@export var base_nest: SceneBuildOption
@export var ship: SceneBuildOption
@export var minimum_cargo: Array[ResourceAmount] = []
@export var revealed_supplies: Array[ResourceAmount] = []
@export_range(50, 1000, 1) var cargo_capacity := 100
@export_range(0, 200, 1) var food_reserve := 30
@export_range(0.01, 1.0, 0.01) var defense_health_fraction := 0.2
@export_range(1, 12, 1) var spider_count := 3
@export var ship_cell := Vector2i(36, 28)
@export var queen_cell := Vector2i(25, 26)
@export var magic_cell := Vector2i(29, 29)
@export var route_cells: Array[Vector2i] = []

