extends Screen
## A readable, paged introduction using the same native pixel controls as the game.
const LESSONS := [
	["ui.tutorial.lesson1.title", "ui.tutorial.lesson1.body"],
	["ui.tutorial.lesson2.title", "ui.tutorial.lesson2.body"],
	["ui.tutorial.lesson3.title", "ui.tutorial.lesson3.body"],
	["ui.tutorial.lesson4.title", "ui.tutorial.lesson4.body"]
]
var controls: Dictionary[StringName, Button] = {}
var _page := 0
var _heading: Label
var _body: Label
var _counter: Label

func _ready() -> void:
	var content: VBoxContainer = ColonyStyle.modal(self, 286)
	_heading = ColonyStyle.label("", 12, ColonyStyle.ACCENT)
	content.add_child(_heading)
	_body = ColonyStyle.label("", 8)
	_body.custom_minimum_size = Vector2(520, 146)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	for entry in [[&"back", "ui.common.main_menu", func(): Router.goto(&"main_menu")], [&"previous", "ui.common.back", func(): _show_page(_page - 1)], [&"next", "ui.common.next", func(): _show_page(_page + 1)], [&"play", "ui.menu.play", func(): Router.goto(&"match")]]:
		var button: Button = ColonyStyle.button(entry[1], entry[0] == &"play")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[2])
		row.add_child(button)
		controls[entry[0]] = button
	_counter = ColonyStyle.label("", 6, ColonyStyle.MUTED)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_counter)
	_show_page(0)

func _show_page(page: int) -> void:
	_page = clampi(page, 0, LESSONS.size() - 1)
	_heading.text = LESSONS[_page][0]
	_body.text = LESSONS[_page][1]
	_counter.text = "%d / %d" % [_page + 1, LESSONS.size()]
	controls[&"previous"].disabled = _page == 0
	controls[&"next"].disabled = _page == LESSONS.size() - 1

func on_focus() -> void:
	controls[&"next"].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Router.goto(&"main_menu")
		get_viewport().set_input_as_handled()
