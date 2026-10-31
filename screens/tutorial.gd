extends Screen
## A readable, paged introduction using the same native pixel controls as the game.
const LESSONS := [
	["Запросы колонии", "Одновременно доступны три запроса ресурсов.\nСдавайте ресурсы и получайте дополнительные секунды и знаки колонии.\nЕсли таймер обнулится, партия закончится поражением.\n\nЗапасы нужны и для заданий, и для строительства.\nМуравьи выбирают близкую и свободную работу."],
	["Награды и развитие", "На уровне пять запросов в случайном порядке.\nОтказ обычно стоит треть цены, не даёт награды и закрывает запрос.\nЦена отказа видна в подсказке кнопки.\n\nЗакрытие уровня меняет цвет дома и даёт улучшение:\nбыстрая дорога, скидка на стройку или скорость муравьёв.\nЗа знаки колонии можно строить новые столовые."],
	["Дороги и пища", "Тропинки ускоряют дорогу на работу и домой.\nДеревья дают древесину, каменоломни — камень, кусты — пищу.\n\nМуравьям нужны еда и безопасный путь к столовой.\nНовый муравейник даёт пять жителей; им тоже нужна пища.\nНагрузка предприятия показана как работают+идут / места."],
	["Стройка на паузе", "Пробел включает стройку и останавливает время и голод.\nВыберите постройку, зажмите ЛКМ и проведите по клеткам.\nДорога и здание помещаются на одной клетке.\n\nПКМ снимает последнее добавление на выбранной клетке.\nCtrl+Z отменяет мазок. Крестик отменяет весь план.\nПробел или треугольник применяют план и продолжают игру."],
	["Камера и снос", "Колесо меняет масштаб, СКМ и WASD двигают камеру.\nВ стройке инструмент «Перемещение» включает перенос ЛКМ.\n\nИнструмент «Снос» отмечает здания и дороги для удаления.\nОтметки применяются вместе с планом, без возврата ресурсов.\nСнос муравейника убивает жителей и требует подтверждения.\nМеню вверху содержит настройки, перезапуск и выход."]
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
	for entry in [[&"back", "В меню", func(): Router.goto(&"main_menu")], [&"previous", "Назад", func(): _show_page(_page - 1)], [&"next", "Далее", func(): _show_page(_page + 1)], [&"play", "Играть", func(): Router.goto(&"match")]]:
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
