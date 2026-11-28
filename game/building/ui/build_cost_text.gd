class_name BuildCostText
extends RefCounted
## Shared wording for individual options and the total construction budget.

const RESOURCE_GAP := "   "
const TIME_ICON: Texture2D = preload("res://graphics/ui/icons/task_time.svg")

## The template can add a localized title around the price.
static func show_price(label: RichTextLabel, costs: Array[ResourceAmount], template := "%s", free_text := "") -> void:
	label.clear()
	label.add_text(template.get_slice("%s", 0))
	_append_totals(label, costs, TranslationServer.translate("ui.cost.free") if free_text.is_empty() else free_text)
	label.add_text(template.get_slice("%s", 1))

static func show_reward(label: RichTextLabel, rewards: Array[ResourceAmount], seconds: float, template := "+ %s") -> void:
	label.clear()
	label.add_text(template.get_slice("%s", 0))
	var has_time := seconds > 0.0
	if has_time:
		var icon_size := label.get_theme_font_size(&"normal_font_size")
		label.add_image(TIME_ICON, icon_size, icon_size)
		label.add_text(" " + String.num(seconds, 2).trim_suffix(".0"))
	_append_totals(label, rewards, "" if has_time else "—", has_time)
	label.add_text(template.get_slice("%s", 1))

static func _append_totals(label: RichTextLabel, costs: Array[ResourceAmount], empty_text: String, has_prefix := false) -> void:
	var totals: Variant = _positive_totals(costs)
	if totals == null:
		label.add_text(TranslationServer.translate("ui.cost.invalid"))
	elif totals.is_empty():
		label.add_text(empty_text)
	else:
		var first := not has_prefix
		for type: ResourceType in totals:
			if not first:
				label.add_text(RESOURCE_GAP)
			first = false
			append_resource(label, type, str(totals[type]))

static func append_resource(label: RichTextLabel, type: ResourceType, amount := "") -> void:
	if type.icon != null:
		var icon_size := label.get_theme_font_size(&"normal_font_size")
		label.add_image(type.icon, icon_size, icon_size)
	else:
		label.add_text(TranslationServer.translate(type.display_name))
	if not amount.is_empty():
		label.add_text(" " + amount)

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
