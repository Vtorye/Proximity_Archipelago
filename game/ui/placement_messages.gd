class_name PlacementMessages
extends RefCounted

static func text(code: PlacementCheck.Code) -> String:
	match code:
		PlacementCheck.Code.OK: return ""
		PlacementCheck.Code.BUSY: return "Дождитесь завершения строительства"
		PlacementCheck.Code.INVALID_OPTION: return "Этот объект недоступен"
		PlacementCheck.Code.RESOURCES: return "Не хватает свободных ресурсов"
		PlacementCheck.Code.INVALID_TILE: return "Недопустимое покрытие"
		PlacementCheck.Code.ALREADY_PLACED: return "Это покрытие уже уложено"
		PlacementCheck.Code.OUTSIDE_MAP: return "За пределами карты строить нельзя"
		PlacementCheck.Code.UNBUILDABLE: return "Это покрытие запрещает строительство"
		PlacementCheck.Code.IMPASSABLE: return "Клетка непроходима"
		PlacementCheck.Code.OCCUPIED: return "Сначала снесите существующее здание"
		PlacementCheck.Code.ANT_PRESENT: return "Подождите, пока муравей освободит клетку"
		PlacementCheck.Code.INVALID_BUILDING: return "Ошибка определения здания"
		PlacementCheck.Code.NO_BUILDING: return "На клетке нет здания"
		PlacementCheck.Code.SPAWN_FOOD: return "Нужны свободные порции пищи для новых жителей"
		PlacementCheck.Code.NO_ESCAPE: return "Это лишит муравьёв безопасного пути к еде"
	return "Действие недоступно"
