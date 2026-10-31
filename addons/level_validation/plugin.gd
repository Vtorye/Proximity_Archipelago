@tool
extends EditorPlugin
func _enter_tree() -> void:
	add_tool_menu_item("Проверить сохранённый уровень", _validate)
func _exit_tree() -> void:
	remove_tool_menu_item("Проверить сохранённый уровень")
func _validate() -> void:
	var scene: Node = EditorInterface.get_edited_scene_root()
	if scene == null or scene.scene_file_path.is_empty():
		push_error("Сначала сохраните сцену уровня")
		return
	var output: Array = []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/validate_level.gd", "--", scene.scene_file_path], output, true)
	for line in output: print(line)
