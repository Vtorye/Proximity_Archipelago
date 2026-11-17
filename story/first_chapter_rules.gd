class_name FirstChapterRules
extends Resource

@export var dialogue: DialogueResource
@export var characters: Array[StoryCharacter] = []
@export var wishes: Array[BuildOption] = []
@export var road: TileBuildOption
@export var ground: TileBuildOption
@export var base_nest: SceneBuildOption
@export var ship: SceneBuildOption
@export var minimum_cargo: Array[ResourceAmount] = []
@export_range(50, 1000, 1) var cargo_capacity := 100
@export_range(0, 200, 1) var food_reserve := 30
@export_range(0.1, 4.0, 0.1) var demolition_interval := 1.2
@export_range(0.01, 1.0, 0.01) var defense_health_fraction := 0.2
@export_range(1, 12, 1) var spider_count := 3
@export_range(1.0, 120.0, 1.0) var demonstration_timeout := 45.0
@export var ship_cell := Vector2i(36, 28)
@export var queen_cell := Vector2i(25, 26)
@export var magic_cell := Vector2i(29, 29)
@export var route_cells: Array[Vector2i] = []

