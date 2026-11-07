class_name DefenseBuilding
extends Building
## A wall blocks movement; a tower reserves one distinct warrior while it is staffed.
enum Kind { WALL, TOWER }
@export var kind: Kind = Kind.WALL
var gunner: AntAgent
var shot_timer := 0.0

func staffed() -> bool:
	return is_instance_valid(gunner) and gunner.status == AntAgent.Status.GUARDING and gunner.combat != null and gunner.combat.tower == self

func _on_demolish() -> void:
	if is_instance_valid(gunner) and gunner.combat != null: gunner.combat.leave_tower()
