extends Screen

var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	controls[&"play"] = %Play
	controls[&"maps"] = %Maps
	controls[&"settings"] = %Settings
	controls[&"language"] = %Language
	controls[&"quit"] = %Quit
	for button: Button in [%Play, %Maps, %Settings, %Language, %Add, %Back, %Load, %Start, %CancelNew, %LoadIsland]:
		button.pressed.connect(AppSettings.play_click)
	%Play.pressed.connect(_show_saves)
	%Maps.pressed.connect(func(): Router.goto(&"level_editor"))
	%Settings.pressed.connect(func(): Router.push_overlay(&"settings"))
	%Language.pressed.connect(_toggle_language)
	%Quit.pressed.connect(AppSettings.quit_game)
	%Back.pressed.connect(_show_actions)
	%Add.pressed.connect(_show_new_game)
	%CancelNew.pressed.connect(_show_saves)
	%Start.pressed.connect(_start_game)
	%Mode.item_selected.connect(func(index: int): %EndlessOptions.visible = index == 1)
	%SaveList.item_activated.connect(_load_save)
	%Load.pressed.connect(_load_selected)
	%SaveList.item_selected.connect(_select_save)
	%IslandList.item_activated.connect(_load_island)
	%LoadIsland.pressed.connect(_load_selected_island)

func _show_actions() -> void:
	%IslandPane.hide()
	%Saves.hide()
	%Actions.show()
	on_focus()

func _show_saves() -> void:
	%IslandPane.hide()
	%SaveList.clear()
	for path: String in SessionSave.paths():
		var saved := SessionSave.read(path)
		if saved.is_empty():
			continue
		var label := tr("ui.play.legacy")
		if path != SessionSave.PATH or saved.has("voyage"):
			var mode := "ui.play.endless" if saved.layout.get("endless", false) else "ui.play.campaign"
			var modified := FileAccess.get_modified_time(path if FileAccess.file_exists(path) else path + ".bak")
			label = "%s · %s" % [tr(mode), Time.get_datetime_string_from_unix_time(modified, true)]
		var index: int = %SaveList.add_item(label)
		%SaveList.set_item_metadata(index, {"path": path, "campaign": saved.has("voyage")})
	%Load.disabled = %SaveList.item_count == 0
	%Load.hide()
	%Actions.hide()
	%NewGame.hide()
	%Saves.show()
	%Add.grab_focus()

func _show_new_game() -> void:
	%IslandPane.hide()
	%Saves.hide()
	%NewGame.show()
	%Mode.grab_focus()

func _start_game() -> void:
	var layout: Dictionary
	if %Mode.selected == 1:
		var waves: bool = %WavesOption.button_pressed
		layout = LevelStore.load_level(LevelStore.starting_level(waves))
		layout["endless"] = true
		layout["wave_mode"] = waves
		layout["queen_timer"] = %TimerOption.button_pressed
	else:
		layout = {"tutorial": true}
	layout["save_path"] = SessionSave.new_path()
	layout["save_on_start"] = true
	Router.goto(&"match", layout)

func _load_selected() -> void:
	var selected: PackedInt32Array = %SaveList.get_selected_items()
	if not selected.is_empty():
		_load_save(selected[0])

func _select_save(index: int) -> void:
	var entry: Dictionary = %SaveList.get_item_metadata(index)
	%Load.visible = not entry.campaign
	if entry.campaign:
		_show_islands(entry.path)
	else:
		%IslandPane.hide()

func _show_islands(path: String) -> void:
	var latest := SessionSave.read(path)
	if latest.is_empty():
		_show_saves()
		return
	var islands := SessionSave.island_paths(path)
	islands[SessionSave.island_number(latest)] = path
	var numbers := islands.keys()
	numbers.sort()
	%IslandList.clear()
	for number: int in numbers:
		var index: int = %IslandList.add_item(tr("ui.play.island_number") % number)
		%IslandList.set_item_metadata(index, {"path": islands[number], "campaign_path": path})
		if islands[number] == path:
			%IslandList.select(index)
	%IslandPane.show()

func _load_selected_island() -> void:
	var selected: PackedInt32Array = %IslandList.get_selected_items()
	if not selected.is_empty():
		_load_island(selected[0])

func _load_island(index: int) -> void:
	var entry: Dictionary = %IslandList.get_item_metadata(index)
	_restore_save(entry.path, entry.campaign_path)

func _load_save(index: int) -> void:
	var entry: Dictionary = %SaveList.get_item_metadata(index)
	if entry.campaign:
		_select_save(index)
	else:
		_restore_save(entry.path, entry.path)

func _restore_save(path: String, slot: String) -> void:
	var saved := SessionSave.read(path)
	if saved.is_empty():
		_show_saves()
		return
	var layout: Dictionary = saved.layout.duplicate()
	layout["snapshot"] = saved
	layout["save_path"] = slot
	Router.goto(&"match", layout)

func on_focus() -> void:
	%Play.grab_focus()

func _toggle_language() -> void:
	AppSettings.language = "en" if TranslationServer.get_locale().begins_with("ru") else "ru"
	var error := AppSettings.save()
	if error != OK:
		push_warning("Could not save language preference: %s" % error_string(error))
