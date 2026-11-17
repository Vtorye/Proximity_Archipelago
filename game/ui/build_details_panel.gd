class_name BuildDetailsPanel
extends PanelContainer
## Shared details for catalog buildings and task offers.
var _controller: BuildController
var _option: BuildOption
var _cell: Vector2i
var _source_parameters := PackedStringArray()
@onready var header: WindowHeader = %WindowHeader

func _ready() -> void:
	header.close_requested.connect(hide)
	AppSettings.language_changed.connect(_refresh_language)

func toggle(option: BuildOption, controller: BuildController, cell: Vector2i) -> void:
	if visible and _option == option:
		hide()
		return
	_controller = controller
	_option = option
	_cell = cell
	_read_source_template(_option)
	_refresh_description(_option)
	show()

func refresh_at(cell: Vector2i) -> void:
	if not visible or _option == null:
		return
	_cell = cell
	_refresh_description(_option)

func _refresh_language() -> void:
	if _option == null:
		return
	_read_source_template(_option)
	refresh_at(_cell)

func _refresh_description(option: BuildOption) -> void:
	header.set_title(option.display_name)
	%Description.text = tr(option.description)
	var price: Array[ResourceAmount] = _controller.price(option, _cell)
	var details := PackedStringArray()
	var size := _footprint_size(option)
	details.append(tr("ui.construction.size") % [size.x, size.y])
	if option is NestBuildOption:
		details.append(tr("ui.construction.residents") % option.resident_capacity)
		details.append(tr("ui.construction.storage") % option.stock_capacity())
	if _controller.construction != null and ConstructionService.needs_builders(option, price):
		details.append(tr("ui.construction.time") % str(option.construction_seconds))
	else:
		details.append(tr("ui.construction.instant"))
	if option is SceneBuildOption:
		if option.requires_water: details.append(tr("ui.construction.water"))
		details.append_array(_source_parameters)
	elif option is WorkplaceUpgradeOption:
		details.append(tr("ui.construction.slots") % option.added_slots)
		var source := _controller.registry.at(_cell) as Workplace
		if source != null and source.matches_improvement(option):
			var slots: int = source.work_slots + (option.added_slots if source.accepts_improvement(option) else 0)
			_append_source_parameters(details, source, slots)
		else:
			details.append(tr("ui.construction.source_target"))
	elif option is TileBuildOption:
		var terrain_map := _controller.map as TerrainMap
		if terrain_map != null:
			var terrain: TerrainType = terrain_map.catalog.for_tile(Vector4i(option.source_id, option.atlas_coords.x, option.atlas_coords.y, option.alternative_tile))
			if terrain != null and terrain.kind == TerrainType.Kind.ROAD:
				details.append(tr("ui.construction.speed") % String.num(terrain.move_cost, 2))
				if terrain.move_cost > 0.0:
					details.append(tr("ui.construction.speed_multiplier") % String.num(AntMotion.speed_multiplier(terrain.move_cost), 2))
	_update_price_growth(option, details)
	%Parameters.text = "\n".join(details)
	BuildCostText.show_price(%Price, price, tr("ui.construction.price"))

func _read_source_template(option: BuildOption) -> void:
	var source_type: ResourceType
	_source_parameters.clear()
	if option is WorkplaceUpgradeOption:
		source_type = option.source_type
	elif option is SceneBuildOption and option.scene != null:
		# Read the authored defaults once per selection, without starting a runtime workplace.
		var template: Node = option.scene.instantiate()
		if template is Workplace and template.recipe == null and template.output != null:
			source_type = template.output
			_append_source_parameters(_source_parameters, template, template.work_slots)
		template.free()
	var resource: RichTextLabel = %ProductionResource
	resource.visible = source_type != null
	if resource.visible:
		resource.clear()
		resource.add_text(tr("ui.construction.production_resource") + " ")
		BuildCostText.append_resource(resource, source_type)

func _append_source_parameters(details: PackedStringArray, source: Workplace, slots: int) -> void:
	details.append(tr("ui.construction.production_slots") % slots)
	var output: float = source.resource_rate()
	details.append(tr("ui.construction.production_rate") % String.num(output, 2).trim_suffix(".0"))
	details.append(tr("ui.source.remaining") % source.remaining_supply if source.finite_supply and _controller.inventory.quantities_known else tr("ui.source.infinite"))

func _footprint_size(option: BuildOption) -> Vector2i:
	var cells: Array[Vector2i] = _controller.footprint_at(option, Vector2i.ZERO)
	if cells.is_empty():
		return Vector2i.ZERO
	var first: Vector2i = cells[0]
	var last: Vector2i = first
	for cell in cells:
		first = first.min(cell)
		last = last.max(cell)
	return last - first + Vector2i.ONE

func _update_price_growth(option: BuildOption, details: PackedStringArray) -> void:
	var event := GameEvents.Kind.TERRAIN_CHANGED if option is TileBuildOption else GameEvents.Kind.BUILDING_BUILT
	var next_price: RichTextLabel = %NextPrice
	if _controller.prices != null:
		var changes_price := false
		for rule in _controller.prices.price_rules(option):
			if rule == null or rule.event != event or (rule.subject != &"" and rule.subject != option.id):
				continue
			if (rule.operation == 0 and rule.value == 1.0) or (rule.operation == 1 and rule.value == 0.0):
				continue
			if rule.resource != null and not _controller.prices.base_costs(option).any(func(cost: ResourceAmount) -> bool:
				return cost != null and cost.type != null and cost.type.id == rule.resource.id):
				continue
			changes_price = true
			var key := "ui.construction.price_multiplier" if rule.operation == 0 else "ui.construction.price_add"
			if rule.resource != null:
				key = "ui.construction.price_partial_multiplier" if rule.operation == 0 else "ui.construction.price_partial_add"
			details.append(tr(key) % String.num(rule.value).trim_suffix(".0"))
		if changes_price:
			var pending: Dictionary[String, int] = {
				PriceService.key(event, option.id): 1,
				PriceService.key(event, &""): 1,
			}
			BuildCostText.show_price(next_price, _controller.price(option, _cell, pending),
				tr("ui.construction.next_price"))
			next_price.show()
			return
	next_price.hide()
	if option is SceneBuildOption:
		details.append(tr("ui.construction.price_constant"))
