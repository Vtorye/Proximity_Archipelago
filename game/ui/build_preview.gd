class_name BuildPreview
extends Node2D

const PRESENTATION: UiPresentation = preload("res://game/ui/ui_presentation.tres")
## World-space ghosts use the same catalog and cell size as committed buildings.
var draft: BuildDraft
var art: ArtCatalog
var hover := Vector2i.ZERO
var hovering := false
var option: BuildOption
var order: TaskBuildOrder
var demolishing := false

func _draw() -> void:
	if draft == null: return
	var color: Color = ColonyStyle.color(&"accent") if draft.budget_check().allowed() else ColonyStyle.color(&"danger")
	var commands: Array[BuildCommand] = draft.commands()
	for terrain in [true, false]:
		for command in commands:
			if not command.is_removal() and (command.option is TileBuildOption) == terrain:
				_draw_option(command.cell, command.option, Color.WHITE, color)
	for command in commands:
		if command.is_removal():
			_draw_removal(draft.footprint(command))
	if hovering and demolishing:
		var building: Building = draft.controller.registry.at(hover)
		var cells: Array[Vector2i] = [hover]
		if building != null: cells = building.footprint()
		_draw_removal(cells)
	if hovering and option != null:
		var check: PlacementCheck = draft.controller.placement_check(option, hover, draft.removals(), order)
		var border: Color = ColonyStyle.color(&"green") if check.allowed() else ColonyStyle.color(&"danger")
		_draw_option(hover, option, Color(Color.WHITE, PRESENTATION.ghost_hover_opacity), border)

func _draw_option(cell: Vector2i, definition: BuildOption, tint: Color, border: Color) -> void:
	var navigation: RouteService = draft.controller.route_service
	var size: Vector2 = Vector2.ONE * navigation.cell_size()
	var occupied: Array[Vector2i] = draft.controller.footprint_at(definition, cell)
	var min_cell := cell
	var max_cell := cell
	for target in occupied:
		min_cell.x = mini(min_cell.x, target.x)
		min_cell.y = mini(min_cell.y, target.y)
		max_cell.x = maxi(max_cell.x, target.x)
		max_cell.y = maxi(max_cell.y, target.y)
	var footprint_size := Vector2(max_cell - min_cell + Vector2i.ONE) * size
	var center_cell := (Vector2(min_cell + max_cell) + Vector2.ONE) * 0.5
	var center: Vector2 = to_local(navigation.cell_to_world(cell)) + (center_cell - Vector2(cell) - Vector2.ONE * 0.5) * size
	var rect := Rect2(center - footprint_size / 2.0, footprint_size)
	var texture: Texture2D = art.build_icon(definition)
	if definition.id == &"house":
		tint *= House.BARRACKS_TINT
	if texture != null:
		draw_texture_rect(texture, rect, false, Color(tint, PRESENTATION.ghost_opacity * tint.a))
	for target in occupied:
		var point: Vector2 = to_local(navigation.cell_to_world(target))
		draw_rect(Rect2(point - size / 2.0 + Vector2.ONE * PRESENTATION.outline_inset, size - Vector2.ONE * PRESENTATION.outline_inset * 2), border, false, PRESENTATION.outline_width)

func _draw_removal(cells: Array[Vector2i]) -> void:
	var navigation: RouteService = draft.controller.route_service
	var size: Vector2 = Vector2.ONE * navigation.cell_size()
	for cell in cells:
		var center: Vector2 = to_local(navigation.cell_to_world(cell))
		var rect := Rect2(center - size / 2.0 + Vector2.ONE * PRESENTATION.outline_inset, size - Vector2.ONE * PRESENTATION.outline_inset * 2)
		draw_rect(rect, PRESENTATION.removal_fill)
		draw_rect(rect, ColonyStyle.color(&"danger"), false, PRESENTATION.outline_width)
		draw_line(rect.position, rect.end, ColonyStyle.color(&"danger"), PRESENTATION.outline_width)
		draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), ColonyStyle.color(&"danger"), PRESENTATION.outline_width)
