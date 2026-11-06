class_name PlacementMessages
extends RefCounted

static func text(code: PlacementCheck.Code) -> String:
	match code:
		PlacementCheck.Code.OK: return ""
		PlacementCheck.Code.BUSY: return TranslationServer.translate("ui.placement.busy")
		PlacementCheck.Code.INVALID_OPTION: return TranslationServer.translate("ui.placement.invalid_option")
		PlacementCheck.Code.RESOURCES: return TranslationServer.translate("ui.placement.resources")
		PlacementCheck.Code.INVALID_TILE: return TranslationServer.translate("ui.placement.invalid_tile")
		PlacementCheck.Code.ALREADY_PLACED: return TranslationServer.translate("ui.placement.already_placed")
		PlacementCheck.Code.OUTSIDE_MAP: return TranslationServer.translate("ui.placement.outside_map")
		PlacementCheck.Code.UNBUILDABLE: return TranslationServer.translate("ui.placement.unbuildable")
		PlacementCheck.Code.STOCK_DEPOT: return TranslationServer.translate("ui.storage.protected")
		PlacementCheck.Code.IMPASSABLE: return TranslationServer.translate("ui.placement.impassable")
		PlacementCheck.Code.OCCUPIED: return TranslationServer.translate("ui.placement.occupied")
		PlacementCheck.Code.ANT_PRESENT: return TranslationServer.translate("ui.placement.ant_present")
		PlacementCheck.Code.INVALID_BUILDING: return TranslationServer.translate("ui.placement.invalid_building")
		PlacementCheck.Code.NO_BUILDING: return TranslationServer.translate("ui.placement.no_building")
		PlacementCheck.Code.NO_ESCAPE: return TranslationServer.translate("ui.placement.no_escape")
	return TranslationServer.translate("ui.placement.unavailable")
