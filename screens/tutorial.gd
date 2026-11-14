extends Screen
## A readable, paged introduction using the same native pixel controls as the game.
const LESSONS := [
	["ui.tutorial.lesson1.title", "ui.tutorial.lesson1.body"],
	["ui.tutorial.progress.title", "ui.tutorial.progress.body"],
	["ui.tutorial.lesson2.title", "ui.tutorial.lesson2.body"],
	["ui.tutorial.lesson3.title", "ui.tutorial.lesson3.body"],
	["ui.tutorial.lesson4.title", "ui.tutorial.lesson4.body"],
]
var controls: Dictionary[StringName, Button] = {}
var _page := 0
@onready var _heading: Label = %Heading
@onready var _body: Label = %Body
@onready var _counter: Label = %Counter

func _ready() -> void:
	ColonyStyle.apply(self)
	controls[&"back"] = %Back
	%Back.pressed.connect(AppSettings.play_click)
	%Back.pressed.connect(func(): Router.goto(&"main_menu"))
	controls[&"previous"] = %Previous
	%Previous.pressed.connect(AppSettings.play_click)
	%Previous.pressed.connect(func(): _show_page(_page - 1))
	controls[&"next"] = %Next
	%Next.pressed.connect(AppSettings.play_click)
	%Next.pressed.connect(func(): _show_page(_page + 1))
	controls[&"play"] = %Play
	%Play.pressed.connect(AppSettings.play_click)
	%Play.pressed.connect(func(): Router.goto(&"match"))
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
