@tool
class_name TerrainCatalog
extends Resource
## Stable tile keys preserve old maps; adding terrain requires only a resource and a catalog entry.
@export var types: Array[TerrainType] = []
@export var default_ground: TerrainType

func by_id(id: StringName) -> TerrainType:
	for type in types:
		if type != null and type.id == id: return type
	return null

func for_tile(key: Vector4i) -> TerrainType:
	for type in types:
		if type != null and type.tile == key: return type
	return null

func install(tiles: TileSet) -> void:
	for type in types:
		if type == null: continue
		var key: Vector4i = type.tile
		if not tiles.has_source(key.x):
			if type.texture == null: continue
			var source := TileSetAtlasSource.new()
			source.texture = type.texture
			source.texture_region_size = Vector2i(type.texture.get_size())
			source.create_tile(Vector2i(key.y, key.z))
			tiles.add_source(source, key.x)
		var atlas := tiles.get_source(key.x) as TileSetAtlasSource
		if atlas == null or not atlas.has_tile(Vector2i(key.y, key.z)): continue
		if type.texture != null:
			atlas.texture = type.texture
			atlas.texture_region_size = Vector2i(type.texture.get_size())
		var data: TileData = atlas.get_tile_data(Vector2i(key.y, key.z), key.w)
		if data == null: continue
		data.set_custom_data("move_cost", type.move_cost)
		data.set_custom_data("walkable", type.kind != TerrainType.Kind.WATER)
		data.set_custom_data("buildable", type.kind != TerrainType.Kind.WATER)
		data.set_custom_data("terrain_name", type.display_name)

func validate() -> Array[String]:
	var errors: Array[String] = []
	var ids := {}
	var keys := {}
	for type in types:
		if type == null:
			errors.append("missing terrain resource")
			continue
		var prefix: String = type.resource_path if not type.resource_path.is_empty() else str(type.id)
		for error in type.validate(): errors.append(prefix + ": " + error)
		if ids.has(type.id) or keys.has(type.tile): errors.append(prefix + ": duplicate terrain ID or tile")
		ids[type.id] = true
		keys[type.tile] = true
	if default_ground == null or not types.has(default_ground) or default_ground.kind != TerrainType.Kind.LAND: errors.append("missing default ground")
	return errors
