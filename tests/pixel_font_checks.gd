extends RefCounted

static func verify(test: Node, root: Control) -> void:
	var typography: UiTypography = AppSettings.TYPOGRAPHY
	var minimum: int = AppSettings.minimum_text_size()
	var allowed: Array[int] = [maxi(minimum, typography.caption_size), maxi(minimum, typography.compact_button_size), maxi(minimum, typography.body_size), maxi(minimum, typography.heading_size)]
	for item in root.find_children("*", "Control", true, false):
		var control: Control = item
		if not control.is_visible_in_tree() or not (control is Label or control is Button):
			continue
		var pixels: int = control.get_theme_font_size("font_size")
		test.expect(pixels in allowed and control.get_theme_font("font") == ColonyStyle.SECONDARY_FONT and control.get_global_transform().get_scale().is_equal_approx(Vector2.ONE), "text follows the selected theme size without scaling controls")
