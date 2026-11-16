extends Node
## Rebuilds the bundled biome example offline. The game loads its saved cells unchanged.
func _ready() -> void:
	_generate.call_deferred()

func _generate() -> void:
	var source: AuthoredLevel = load("res://game/worlds/maps/tidal_shards.tres")
	var world: World = LevelLayout.create_world(source.data())
	if world == null:
		get_tree().quit(1)
		return
	var map := world.get_node("Map") as TerrainMap
	var objects: Array[Node] = []
	for path in LevelLayout.prototypes(world):
		var building := world.get_node(path) as Building
		if not building.has_meta(&"layout_kind"): building.set_meta(&"layout_kind", path)
		objects.append(building)
	TerrainPainter.populate(map, objects)
	var level := AuthoredLevel.new()
	level.title = "Пять земель"
	level.description = "Плодородные долины, сухие возвышенности и каменистые месторождения. Влажные берега расширяют соседние муравейники; песчаные пляжи удорожают дороги. Нарисованные почвы сохраняются вместе с картой."
	level.layout = LevelLayout.capture(map, objects)
	var error: Error = ResourceSaver.save(level, "res://game/worlds/maps/five_soils.tres")
	world.free()
	print("SOIL MAP SAVED: ", error_string(error))
	get_tree().quit(0 if error == OK else 1)
