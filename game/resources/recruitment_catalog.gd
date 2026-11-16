class_name RecruitmentCatalog
extends Resource
## Recruitment prices are editable independently of population and UI.

@export var worker_costs: Array[ResourceAmount] = []
@export var carrier_costs: Array[ResourceAmount] = []
@export var warrior_costs: Array[ResourceAmount] = []

func price(role: AntAgent.Role) -> Array[ResourceAmount]:
	if role == AntAgent.Role.WARRIOR: return warrior_costs
	return carrier_costs if role == AntAgent.Role.CARRIER else worker_costs
