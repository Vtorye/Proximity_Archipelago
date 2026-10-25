extends Screen
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	ColonyStyle.apply(self)
	var background := ColorRect.new()
	background.color = ColonyStyle.BACKGROUND
	add_child(background)
	ColonyStyle.fill(background)
	var diorama := ColonyBackdrop.new()
	add_child(diorama)
	ColonyStyle.fill(diorama)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.07, 0.07, 0.18)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	ColonyStyle.fill(shade)
	var content := VBoxContainer.new()
	content.position = Vector2(64, 102)
	content.custom_minimum_size = Vector2(440, 0)
	content.add_theme_constant_override("separation", 18)
	add_child(content)
	content.add_child(ColonyStyle.label("PROXIMITY / АРХИПЕЛАГ", 15, ColonyStyle.ACCENT))
	content.add_child(ColonyStyle.label("Маленькая колония.\nБольшие открытия.", 36))
	var description: Label = ColonyStyle.label("Постройте муравейник. Найдите ресурсы.\nПозаботьтесь о каждом муравье.", 18, ColonyStyle.MUTED)
	content.add_child(description)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	content.add_child(spacer)
	var play: Button = ColonyStyle.button("Начать экспедицию", true)
	play.name = "PlayButton"
	play.pressed.connect(func(): Router.goto(&"match"))
	content.add_child(play)
	controls[&"play"] = play
	var settings: Button = ColonyStyle.button("Настройки")
	settings.pressed.connect(func(): Router.push_overlay(&"settings"))
	content.add_child(settings)
	controls[&"settings"] = settings
	var quit: Button = ColonyStyle.button("Выйти из игры")
	quit.pressed.connect(func(): get_tree().quit())
	content.add_child(quit)
	controls[&"quit"] = quit
	var footer: Label = ColonyStyle.label("ЛКМ / ПКМ — выбрать клетку     ·     Esc — пауза", 14, ColonyStyle.MUTED)
	add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(64, 660)

func on_focus() -> void:
	controls[&"play"].grab_focus()
