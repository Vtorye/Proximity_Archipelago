class_name LevelData
extends RefCounted
## In-memory geometry. LevelLayout reads and writes the version 1 file format.

class Placement:
	var cell: Vector2i
	var kind: String
	## A negative amount means the scene supplies its own defaults.
	var remaining_supply := -1
	var finite_supply := false
	var improvement_id: StringName

	func _init(origin: Vector2i, scene_kind: String, amount := -1, finite := false) -> void:
		cell = origin
		kind = scene_kind
		remaining_supply = amount
		finite_supply = finite

## Values hold the TileSet source, two atlas coordinates and the alternative tile.
var tiles: Dictionary[Vector2i, Vector4i] = {}
var underlays: Dictionary[Vector2i, Vector4i] = {}
var objects: Array[Placement] = []
var title := ""
var description := ""
var seed_value := 0
var difficulty := 0
var biome := 0
var generated := false
