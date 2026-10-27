extends RefCounted
## Verify real controls use a native pixel grid, with no affine text scaling.
static func verify(test: Node, root: Control) -> void:
	for item in root.find_children("*", "Control", true, false):
		var control: Control = item
		if not control.is_visible_in_tree() or not (control is Label or control is Button): continue
		var pixels: int = control.get_theme_font_size("font_size")
		var font: Font = control.get_theme_font("font")
		var valid: bool = pixels == 8 and font == ColonyStyle.SECONDARY_FONT or pixels >= 16 and pixels % 16 == 0 and font == ColonyStyle.FONT
		test.expect(valid and control.get_global_transform().get_scale().is_equal_approx(Vector2.ONE), "visible text uses a native pixel font size without fractional transforms")
