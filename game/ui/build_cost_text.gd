class_name BuildCostText
extends RefCounted
## Shared wording for individual options and the total construction budget.

const RESOURCE_GAP := "   "

static func format(costs: Array[ResourceAmount]) -> String:
	var totals: Variant = _positive_totals(costs)
	if totals == null:
		return TranslationServer.translate("ui.cost.invalid")
	var parts := PackedStringArray()
	for type: ResourceType in totals:
		parts.append("%s %d" % [icon(type), totals[type]])
	return RESOURCE_GAP.join(parts) if not parts.is_empty() else TranslationServer.translate("ui.cost.free")

## The template can add a localized title around the price.
static func show_price(label: RichTextLabel, costs: Array[ResourceAmount], template := "%s") -> void:
	label.clear()
	label.add_text(template.get_slice("%s", 0))
	var totals: Variant = _positive_totals(costs)
	if totals == null:
		label.add_text(TranslationServer.translate("ui.cost.invalid"))
	elif totals.is_empty():
		label.add_text(TranslationServer.translate("ui.cost.free"))
	else:
		var icon_size := label.get_theme_font_size(&"normal_font_size")
		var first := true
		for type: ResourceType in totals:
			if not first:
				label.add_text(RESOURCE_GAP)
			first = false
			if type.icon != null:
				label.add_image(type.icon, icon_size, icon_size)
				label.add_text(" ")
			label.add_text(str(totals[type]))
	label.add_text(template.get_slice("%s", 1))

static func _positive_totals(costs: Array[ResourceAmount]) -> Variant:
	var totals: Dictionary[StringName, int] = {}
	var types: Dictionary[StringName, ResourceType] = {}
	for cost in costs:
		if cost == null or cost.type == null or cost.amount < 0:
			return null
		totals[cost.type.id] = totals.get(cost.type.id, 0) + cost.amount
		types[cost.type.id] = cost.type
	var result: Dictionary[ResourceType, int] = {}
	for id in totals:
		if totals[id] > 0:
			result[types[id]] = totals[id]
	return result

static func icon(type: ResourceType) -> String:
	if type == null:
		return "?"
	match type.id:
		&"wood": return "🪵"
		&"stone": return "🪨"
		&"food": return "🍎"
		&"royal": return TranslationServer.translate(type.display_name)
		_: return "◆"
