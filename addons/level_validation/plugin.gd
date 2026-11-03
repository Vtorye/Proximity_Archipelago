@tool
extends EditorPlugin
const DEFAULT_LEVEL := "res://game/worlds/world_1.tscn"
var _dock: ScrollContainer
var _content: VBoxContainer
var _status: Label
var _output: RichTextLabel
var controls: Dictionary[StringName, Button] = {}
func _enter_tree() -> void:
	add_tool_menu_item("Проверить сохранённый уровень", _validate)
	add_tool_menu_item("Открыть инструменты уровня", _show_dock)
	_dock = ScrollContainer.new()
	_dock.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock.add_child(_content)
	_dock.name = "Уровень"
	_dock.custom_minimum_size.x = 230
	var title := Label.new()
	title.text = "Настройка колонии"
	_content.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	_button(&"map", "1. Открыть карту и рисовать", _open_map)
	_button(&"catalog", "2. Постройки и цены", func(): _edit_property(&"build_catalog"))
	_button(&"resources", "3. Начальные ресурсы", _select_world)
	_button(&"tasks", "4. Наборы заданий", func(): _edit_property(&"task_deck"))
	_button(&"tiles", "Свойства и текстуры тайлов", _edit_tiles)
	_button(&"validate", "Проверить сохранённый уровень", _validate)
	var help := Label.new()
	help.text = "Map → TileMap внизу → кисть.\nCtrl+S сохраняет карту.\n\nЦены: Options → постройка → Costs.\nПравила: Price Rules.\nПодробности: docs/DESIGNER_WORKFLOW.md."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(help)
	_output = RichTextLabel.new()
	_output.custom_minimum_size = Vector2(230, 160)
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.selection_enabled = true
	_output.text = "Проверка выводит ошибки здесь. Перед проверкой сохраните сцену и ресурсы."
	_content.add_child(_output)
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)
	scene_changed.connect(_scene_changed)
	_scene_changed(EditorInterface.get_edited_scene_root())
func _exit_tree() -> void:
	remove_tool_menu_item("Проверить сохранённый уровень")
	remove_tool_menu_item("Открыть инструменты уровня")
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
func _button(id: StringName, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	_content.add_child(button)
	controls[id] = button
func _scene_changed(_scene: Node) -> void:
	var world: Node = _world()
	_status.text = "Открыт уровень: %s" % world.name if world != null else "Начните с кнопки 1. Уровень редактируется без запуска игры."
func _world() -> Node:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null: return null
	if root.has_node("Map"): return root
	return root.get_node_or_null("World")
func _open_map() -> void:
	if _world() == null: EditorInterface.open_scene_from_path(DEFAULT_LEVEL)
	await get_tree().process_frame
	var world: Node = _world()
	if world == null: return
	EditorInterface.set_main_screen_editor("2D")
	EditorInterface.edit_node(world.get_node("Map"))
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(world.get_node("Map"))
func _select_world() -> void:
	var world: Node = _world()
	if world == null:
		_output.text = "Сначала откройте карту кнопкой 1."
		return
	EditorInterface.edit_node(world)
func _edit_property(property: StringName) -> void:
	var world: Node = _world()
	if world == null:
		_output.text = "Сначала откройте карту кнопкой 1."
		return
	var resource: Resource = world.get(property)
	if resource == null:
		_output.text = "Уровень не задаёт %s. Выберите корень уровня и назначьте ресурс в Inspector." % property
		_select_world()
		return
	EditorInterface.edit_resource(resource)
func _edit_tiles() -> void:
	var world: Node = _world()
	if world == null: return
	EditorInterface.edit_resource(world.get_node("Map").tile_set)
func _validate() -> void:
	var scene: Node = EditorInterface.get_edited_scene_root()
	if scene == null or scene.scene_file_path.is_empty():
		_output.text = "Сначала сохраните сцену уровня."
		return
	var output: Array = []
	var result: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/validate_level.gd", "--", scene.scene_file_path], output, true)
	_output.text = "Уровень корректен.\n" if result == 0 else "Найдены ошибки. Исправьте данные перед запуском.\n"
	for chunk in output:
		for line in str(chunk).split("\n"):
			if line.is_empty() or line.begins_with("Godot Engine"): continue
			_output.text += line + "\n"
			print(line)

func _show_dock() -> void:
	var child: Node = _dock
	var parent: Node = child.get_parent()
	while parent != null:
		# Godot 4.7 wraps legacy docks in EditorDock; older versions use TabContainer.
		if parent.is_class("EditorDock"):
			parent.call("make_visible")
			return
		if parent is TabContainer:
			parent.current_tab = child.get_index()
			return
		child = parent
		parent = parent.get_parent()
