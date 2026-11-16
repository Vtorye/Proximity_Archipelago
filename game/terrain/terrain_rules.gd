class_name TerrainRules
extends Node
## One query service supplies placement, quotes, yield and adjacency bonuses.
signal changed
var map: TerrainMap
var registry: BuildingRegistry
var _refresh_queued := false

func configure(ground: TerrainMap, buildings: BuildingRegistry) -> void:
	map = ground
	registry = buildings
	registry.added.connect(apply_to)
	map.changed.connect(_queue_refresh)

func allows(option: BuildOption, cell: Vector2i) -> bool:
	return allows_kind(option.placement_kind, cell)

func restricts(option: BuildOption, cell: Vector2i) -> bool:
	var type: TerrainType = map.ground_at(cell)
	return type != null and type.kind == TerrainType.Kind.LAND and not supports(type, option.placement_kind)

func allows_kind(kind: int, cell: Vector2i) -> bool:
	return supports(map.ground_at(cell), kind)

static func supports(type: TerrainType, kind: int) -> bool:
	if type == null or type.kind == TerrainType.Kind.WATER: return false
	match kind:
		BuildOption.PlacementKind.ROAD: return type.roads_allowed
		BuildOption.PlacementKind.BERRY: return type.berries_allowed
		BuildOption.PlacementKind.NEST: return type.nests_allowed
	return true

func price_multiplier(option: BuildOption, cell: Vector2i) -> float:
	var type: TerrainType = map.ground_at(cell)
	if type == null: return 1.0
	match option.placement_kind:
		BuildOption.PlacementKind.ROAD: return type.road_price_multiplier
		BuildOption.PlacementKind.NEST: return type.nest_price_multiplier
	return 1.0

func capacity_multiplier(house: House) -> float:
	var best := 1.0
	var radius := 1
	for type in map.catalog.types: radius = maxi(radius, type.bonus_radius)
	for cell in house.footprint():
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if x == 0 and y == 0: continue
				var type: TerrainType = map.ground_at(cell + Vector2i(x, y))
				if type != null and maxi(absi(x), absi(y)) <= type.bonus_radius:
					best = maxf(best, type.adjacent_capacity_multiplier)
	return best

func apply_to(building: Building) -> void:
	if building is House:
		building.terrain_capacity_multiplier = capacity_multiplier(building)
	elif building is Workplace:
		var type: TerrainType = map.ground_at(building.cell)
		building.terrain_yield_multiplier = type.berry_multiplier if type != null and building.recipe == null and building.output != null and building.output.id == &"food" else 1.0

func refresh_all() -> void:
	_refresh_queued = false
	for building in registry.all(): apply_to(building)
	changed.emit()

func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	refresh_all.call_deferred()

static func building_kind(building: Building) -> int:
	if building is House: return BuildOption.PlacementKind.NEST
	if building is Workplace and building.recipe == null and building.output != null and building.output.id == &"food": return BuildOption.PlacementKind.BERRY
	return building.option.placement_kind if building.option != null else BuildOption.PlacementKind.ANY

static func describe(type: TerrainType) -> String:
	if type == null: return ""
	var yes: String = TranslationServer.translate("ui.terrain.allowed")
	var no: String = TranslationServer.translate("ui.terrain.forbidden")
	var lines := PackedStringArray([TranslationServer.translate(type.display_name)])
	if type.kind == TerrainType.Kind.WATER: return lines[0]
	lines.append(TranslationServer.translate("ui.terrain.permissions") % [yes if type.roads_allowed else no, yes if type.berries_allowed else no, yes if type.nests_allowed else no])
	if not is_equal_approx(type.berry_multiplier, 1): lines.append(TranslationServer.translate("ui.terrain.harvest") % roundi(type.berry_multiplier * 100))
	if not is_equal_approx(type.nest_price_multiplier, 1): lines.append(TranslationServer.translate("ui.terrain.nest_price") % roundi(type.nest_price_multiplier * 100))
	if not is_equal_approx(type.road_price_multiplier, 1): lines.append(TranslationServer.translate("ui.terrain.road_price") % roundi(type.road_price_multiplier * 100))
	if type.adjacent_capacity_multiplier > 1: lines.append(TranslationServer.translate("ui.terrain.adjacency") % [roundi((type.adjacent_capacity_multiplier - 1) * 100), type.bonus_radius])
	return "\n".join(lines)
