class_name ConstructionJob
extends RefCounted
## One ant's exclusive material batch or assembly slot. No stock is duplicated.
var site: ConstructionSite
var source: House
var materials: Array[ResourceAmount] = []
var picked_up := false
var assembly := false

func live() -> bool:
	return is_instance_valid(site) and site.active
