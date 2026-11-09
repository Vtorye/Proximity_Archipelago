class_name PlacementCheck
extends RefCounted
## Stable domain reasons; presentation owns their wording and translation.
enum Code { OK, BUSY, INVALID_OPTION, RESOURCES, INVALID_TILE, ALREADY_PLACED, OUTSIDE_MAP, OCCUPIED, ANT_PRESENT, INVALID_BUILDING, NO_BUILDING, NO_ESCAPE, UNBUILDABLE, IMPASSABLE, STOCK_DEPOT, RESOURCE_SITE, SOIL_RESTRICTED, WATER_REQUIRED, SHORE_REQUIRED, NO_BUILD_SUPPLY }
var code: Code = Code.OK

static func result(reason: Code) -> PlacementCheck:
	var check := PlacementCheck.new()
	check.code = reason
	return check

func allowed() -> bool:
	return code == Code.OK
