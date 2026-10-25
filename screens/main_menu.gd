extends Screen
## Main menu contains only the animated background and three unframed actions.
var controls: Dictionary[StringName, Button] = {}

func _ready() -> void:
	ColonyStyle.apply(self)
	var backdrop := ColonyBackdrop.new()
	add_child(backdrop)
	ColonyStyle.fill(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	ColonyStyle.fill(shade)
	var center := CenterContainer.new()
	add_child(center)
	ColonyStyle.fill(center)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	center.add_child(content)
	_add_action(content, &"play", "Играть", func(): Router.goto(&"match"))
	_add_action(content, &"settings", "Настройки", func(): Router.push_overlay(&"settings"))
	_add_action(content, &"quit", "Выход", AppSettings.quit_game)

func _add_action(parent: VBoxContainer, key: StringName, text: String, action: Callable) -> void:
	var button: Button = ColonyStyle.button(text, false, key != &"quit")
	button.custom_minimum_size = Vector2(208, 34)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(action)
	parent.add_child(button)
	controls[key] = button

func on_focus() -> void:
	controls[&"play"].grab_focus()
