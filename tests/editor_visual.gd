@tool
extends RefCounted
## Runs only in an isolated editor copy prepared by check_editor_ui.sh.
var failures: Array[String] = []
var assertions := 0
func expect(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		failures.append(description)
		print("EDITOR FAIL ", description)
func frames(plugin: EditorPlugin, count: int = 20) -> void:
	for index in range(count): await plugin.get_tree().process_frame
func run(plugin: EditorPlugin) -> void:
	await frames(plugin, 40)
	plugin._show_dock()
	await frames(plugin)
	expect(plugin._dock.is_visible_in_tree(), "level tools are visible when opened from the Tools menu")
	plugin.controls[&"map"].pressed.emit()
	await frames(plugin, 80)
	var root: Node = EditorInterface.get_edited_scene_root()
	expect(root != null and root.has_node("Map"), "map button opens the authored level")
	expect(EditorInterface.get_selection().get_selected_nodes().has(root.get_node("Map")), "map button selects the paintable TileMapLayer")
	await capture(plugin, "01-map-painting")
	var map: TileMapLayer = root.get_node("Map")
	map.set_cell(Vector2i(-1, 0), 3, Vector2i(1, 0))
	EditorInterface.mark_scene_as_unsaved()
	expect(EditorInterface.save_scene() == OK, "painted tiles save through the editor")
	var saved: Node = ResourceLoader.load(root.scene_file_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	expect(saved.get_node("Map").get_used_rect().position.x == -1, "saved maps preserve newly painted cells outside the original bounds")
	saved.free()
	map.erase_cell(Vector2i(-1, 0))
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()
	plugin.controls[&"catalog"].pressed.emit()
	await frames(plugin)
	var catalog: Object = EditorInterface.get_inspector().get_edited_object()
	expect(catalog is Resource and catalog.get("options").size() > 0, "catalog button opens editable construction definitions")
	await capture(plugin, "02-construction-catalog")
	plugin.controls[&"resources"].pressed.emit()
	await frames(plugin)
	expect(EditorInterface.get_inspector().get_edited_object() == root, "resources button selects the world inspector")
	plugin.controls[&"tasks"].pressed.emit()
	await frames(plugin)
	expect(EditorInterface.get_inspector().get_edited_object().get("stages").size() == 3, "tasks button opens the prepared deck")
	await capture(plugin, "03-task-deck")
	plugin.controls[&"validate"].pressed.emit()
	expect(plugin._output.text.begins_with("Уровень корректен"), "saved level validation is visible in the dock")
	await capture(plugin, "04-level-validation")
	var path := "res://game/building/options/house.tres"
	var original: String = FileAccess.get_file_as_string(path)
	FileAccess.open(path, FileAccess.WRITE).store_string(original.replace("amount = 10", "amount = -10"))
	plugin.controls[&"validate"].pressed.emit()
	expect(plugin._output.text.begins_with("Найдены ошибки") and plugin._output.text.contains("house.tres"), "bad prices are reported with the resource path")
	FileAccess.open(path, FileAccess.WRITE).store_string(original)
	await capture(plugin, "05-invalid-price-path")
	var report := {"assertions": assertions, "failures": failures}
	FileAccess.open(OS.get_environment("COLONY_CAPTURE_DIR").path_join("editor-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("EDITOR REPORT ", JSON.stringify(report))
	print("EDITOR TESTS PASS" if failures.is_empty() else "EDITOR TESTS FAIL")
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
func capture(plugin: EditorPlugin, label: String) -> void:
	await frames(plugin, 15)
	RenderingServer.force_draw()
	plugin.get_viewport().get_texture().get_image().save_png(OS.get_environment("COLONY_CAPTURE_DIR").path_join(label + ".png"))
