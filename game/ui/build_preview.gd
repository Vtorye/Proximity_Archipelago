class_name BuildPreview
extends Node2D
## World-space ghosts use the same catalog and cell size as committed buildings.
var draft: BuildDraft
var art: ArtCatalog
var hover := Vector2i.ZERO
var hovering := false
var option: BuildOption
var demolishing := false

func _draw() -> void:
	if draft == null: return
	var color: Color = ColonyStyle.ACCENT if draft.budget_check().allowed() else ColonyStyle.DANGER
	var commands: Array[BuildCommand] = draft.commands()
	for terrain in [true, false]:
		for command in commands:
			if not command.is_removal() and (command.option is TileBuildOption) == terrain:
				_draw_option(command.cell, command.option, Color.WHITE, color)
	for command in commands:
		if command.is_removal(): _draw_removal(command.removed_building.footprint())
	if hovering and demolishing:
		var building: Building = draft.controller.registry.at(hover)
		var cells: Array[Vector2i] = [hover]
		if building != null: cells = building.footprint()
		_draw_removal(cells)
	if hovering and option != null:
		var check: PlacementCheck = draft.controller.placement_check(option, hover, draft.removals())
		var border: Color = ColonyStyle.GREEN if check.allowed() else ColonyStyle.DANGER
		_draw_option(hover, option, Color(1, 1, 1, 0.5), border)

func _draw_option(cell: Vector2i, definition: BuildOption, tint: Color, border: Color) -> void:
	var navigation: RouteService = draft.controller.route_service
	var size: Vector2 = Vector2.ONE * navigation.cell_size()
	var center: Vector2 = to_local(navigation.cell_to_world(cell))
	var rect := Rect2(center - size / 2.0, size)
	var texture: Texture2D = definition.icon if definition.icon != null else BuildChoiceButton.default_icon(definition, art)
	if texture != null:
		draw_texture_rect(texture, rect, false, Color(tint, 0.65 * tint.a))
	for target in draft.controller.footprint_at(definition, cell):
		var point: Vector2 = to_local(navigation.cell_to_world(target))
		draw_rect(Rect2(point - size / 2.0 + Vector2.ONE, size - Vector2.ONE * 2), border, false, 1.0)

func _draw_removal(cells: Array[Vector2i]) -> void:
	var navigation: RouteService = draft.controller.route_service
	var size: Vector2 = Vector2.ONE * navigation.cell_size()
	for cell in cells:
		var center: Vector2 = to_local(navigation.cell_to_world(cell))
		var rect := Rect2(center - size / 2.0 + Vector2.ONE, size - Vector2.ONE * 2)
		draw_rect(rect, Color(0.6, 0.1, 0.1, 0.4))
		draw_rect(rect, ColonyStyle.DANGER, false, 1.0)
		draw_line(rect.position, rect.end, ColonyStyle.DANGER, 1.0)
		draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), ColonyStyle.DANGER, 1.0)
