class_name LevelValidator
extends RefCounted
## Runs on saved authored data without entering the world or creating agents.
static func validate(path: String) -> Array[String]:
	var errors: Array[String] = []
	var scene: PackedScene = load(path) as PackedScene
	if scene == null: return [path + ": cannot load level"]
	var root: Node = scene.instantiate()
	var world: World = root as World
	if world == null:
		root.free()
		return [path + ": root must be World"]
	var map: TileMapLayer = world.get_node_or_null("Map") as TileMapLayer
	if map == null or map.tile_set == null or map.get_used_cells().is_empty():
		errors.append(path + ": missing painted TileMap/TileSet")
	else:
		var grid := TileGrid.new()
		grid.setup(map, [])
		var buildings: Array[Building] = []
		world._collect_buildings(world, buildings)
		var food: Array[Vector2i] = []
		for building in buildings:
			building.cell = map.local_to_map(map.to_local(building.global_position))
			for error in building.validate_definition(): errors.append(path + ":" + str(world.get_path_to(building)) + ": " + error)
			if building is Canteen: food.append_array(building.entry_cells())
			if building.option is SceneBuildOption and building.option.blocks_movement:
				var changes: Dictionary[Vector2i, float] = {}
				for cell in building.footprint(): changes[cell] = 0.0
				grid = grid.with_costs(changes)
		var field: NavigationField = GridSearch.build(grid, food, true)
		for building in buildings:
			var prefix: String = path + ":" + str(world.get_path_to(building))
			var reachable := false
			for entry in building.entry_cells(): reachable = reachable or is_finite(field.cost(entry))
			if not reachable: errors.append(prefix + ": no accessible entry or route to food")
			if building is House and reachable:
				var nearest := INF
				for entry in building.entry_cells(): nearest = minf(nearest, field.cost(entry))
				var speed: float = building.option.spawn_speed if building.option is SceneBuildOption else 24.0
				if nearest * map.tile_set.tile_size.x / speed * 2.25 + AntNeeds.MEAL_SECONDS + AntNeeds.SAFETY_MARGIN > AntNeeds.CAPACITY:
					errors.append(prefix + ": food is beyond a resident's energy budget")
		var stock := WorldInventory.new()
		var types: Dictionary[StringName, bool] = {}
		for entry in world.starting_resources:
			if entry == null or entry.type == null or entry.amount < 0: errors.append(path + ": invalid starting resource")
			elif types.has(entry.type.id): errors.append(path + ": duplicate resource " + str(entry.type.id))
			else: types[entry.type.id] = true
		for building in buildings:
			if building is Workplace:
				var ingredients: Array[ResourceAmount] = []
				if building.recipe != null: ingredients.append_array(building.recipe.inputs); ingredients.append_array(building.recipe.outputs)
				elif building.output != null:
					var product := ResourceAmount.new()
					product.type = building.output
					ingredients.append(product)
				for entry in ingredients:
					if entry == null or entry.type == null or not types.has(entry.type.id): errors.append(path + ":" + str(world.get_path_to(building)) + ": unknown recipe resource")
		var options: Array[BuildOption] = world.build_catalog.options if world.build_catalog != null else world.build_options
		var ids: Dictionary[StringName, bool] = {}
		var prices := PriceService.new()
		for option in options:
			if option == null:
				errors.append(path + ": missing catalog option")
				continue
			var prefix: String = option.resource_path if not option.resource_path.is_empty() else path
			if option.id == &"" or ids.has(option.id): errors.append(prefix + ": missing or duplicate build ID")
			ids[option.id] = true
			if not prices.valid(option): errors.append(prefix + ": invalid price or event rule")
			for rule in option.price_rules:
				if rule != null and rule.resource != null and not types.has(rule.resource.id): errors.append(prefix + ": unknown rule resource " + str(rule.resource.id))
			for cost in option.costs:
				if cost != null and cost.type != null and not types.has(cost.type.id): errors.append(prefix + ": unknown resource " + str(cost.type.id))
			if option is SceneBuildOption:
				if option.blocks_movement and option.entry_offsets.is_empty(): errors.append(prefix + ": blocking building has no entrance")
				if option.scene == null: errors.append(prefix + ": missing building scene")
				else:
					var candidate: Node = option.scene.instantiate()
					if candidate is Building:
						for error in candidate.validate_definition(): errors.append(prefix + ": " + error)
					else: errors.append(prefix + ": scene root is not a Building")
					candidate.free()
		prices.free()
		stock.free()
	world.free()
	return errors
