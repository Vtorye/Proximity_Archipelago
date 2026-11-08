@tool
class_name TerrainType
extends Resource
## A designer-owned ground definition. TileSet movement data is derived from this resource.
enum Kind { LAND, ROAD, WATER }
@export var id: StringName
@export var display_name: String
@export var tile := Vector4i(-1, 0, 0, 0)
@export var texture: Texture2D:
	set(value):
		texture = value
		emit_changed()
@export var kind: Kind = Kind.LAND
@export_range(0.0, 10.0, 0.05) var move_cost := 1.6
@export var roads_allowed := true
@export var berries_allowed := true
@export var nests_allowed := true
@export_range(0.0, 5.0, 0.05) var berry_multiplier := 1.0
@export_range(0.0, 5.0, 0.05) var nest_price_multiplier := 1.0
@export_range(0.0, 5.0, 0.05) var road_price_multiplier := 1.0
@export_range(1.0, 5.0, 0.05) var adjacent_capacity_multiplier := 1.0
@export_range(1, 8) var bonus_radius := 1
## The ordinary soil brush restores the original ground when removing a road.
@export var preserve_ground := false
@export var restores_ground := false

func validate() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or display_name.is_empty() or tile.x < 0: errors.append("missing terrain ID, name or tile")
	if not is_finite(move_cost) or move_cost < 0 or (kind != Kind.WATER and move_cost <= 0): errors.append("invalid movement cost")
	for value in [berry_multiplier, nest_price_multiplier, road_price_multiplier, adjacent_capacity_multiplier]:
		if not is_finite(value) or value < 0: errors.append("invalid terrain multiplier")
	if adjacent_capacity_multiplier < 1 or bonus_radius < 1: errors.append("invalid adjacency bonus")
	return errors
