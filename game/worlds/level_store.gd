class_name LevelStore
extends RefCounted

const DIRECTORY := "user://maps"
const MAX_BYTES := 32 * 1024 * 1024
const BUILT_IN_LEVELS := {
	"builtin/tidal_shards": preload("res://game/worlds/maps/tidal_shards.tres"),
}

static func save_level(title: String, layout: Dictionary) -> Error:
	title = title.strip_edges()
	if title.is_empty() or title.length() > 64:
		return ERR_INVALID_PARAMETER
	var data: Dictionary = layout.duplicate()
	data["title"] = title
	var content: String = JSON.stringify(data)
	if content.to_utf8_buffer().size() > MAX_BYTES:
		return ERR_OUT_OF_MEMORY
	var error: Error = DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error != OK:
		return error
	var path: String = DIRECTORY.path_join(title.sha256_text() + ".json")
	var temporary: String = path + ".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error

static func saved_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for id: String in BUILT_IN_LEVELS:
		levels.append({"file": id, "title": BUILT_IN_LEVELS[id].title})
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		return levels
	for filename in DirAccess.get_files_at(DIRECTORY):
		if filename.get_extension() != "json":
			continue
		var data: Dictionary = load_level(filename)
		var title: Variant = data.get("title")
		if title is String and not title.is_empty():
			levels.append({"file": filename, "title": title})
	levels.sort_custom(func(a: Dictionary, b: Dictionary): return a.title.naturalnocasecmp_to(b.title) < 0)
	return levels

static func load_level(filename: String) -> Dictionary:
	if BUILT_IN_LEVELS.has(filename):
		return BUILT_IN_LEVELS[filename].data()
	if filename.length() != 69 or filename.get_extension() != "json" or not filename.get_basename().is_valid_hex_number():
		return {}
	var file := FileAccess.open(DIRECTORY.path_join(filename), FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data: Variant = json.data
	if not data is Dictionary or data.get("version") != LevelLayout.VERSION:
		return {}
	var title: Variant = data.get("title")
	if not title is String or title.strip_edges().is_empty() or title.length() > 64:
		return {}
	return data
