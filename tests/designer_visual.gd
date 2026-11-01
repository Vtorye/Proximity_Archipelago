extends "res://tests/ui_runner.gd"
func _run() -> void:
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(40)
	await click(Router._current.controls[&"play"])
	await frames(40)
	screen = Router._current
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 1, "N shows milliseconds per cell")
	await capture("01-entry-milliseconds", 30)
	await _check_full_map_overlay()
	await key(KEY_N)
	await click_at(cell_point(Vector2i(24, 25)))
	expect(screen.navigation_overlay.origin == Vector2i(24, 25), "left click picks the distance origin")
	await capture("02-distance-and-job-scores", 30)
	await key(KEY_SPACE)
	var menu: ConstructionMenu = Router.top_overlay() as ConstructionMenu
	expect(menu.controls[&"house"].cost_label.text == "10 Древесина + 20 Камень", "menu shows the configured composite nest price")
	await capture("03-configured-house-price", 30)
	var path := "res://game/building/options/house.tres"
	var original := FileAccess.get_file_as_string(path)
	await frames(65)
	FileAccess.open(path, FileAccess.WRITE).store_string(original.replace("amount = 10", "amount = 15"))
	await frames(90)
	expect(menu.controls[&"house"].cost_label.text == "15 Древесина + 20 Камень", "saved configuration edits update an already open menu")
	await capture("04-live-price-reload", 30)
	FileAccess.open(path, FileAccess.WRITE).store_string(original)
	await frames(65)
	await key(KEY_SPACE)
	await key(KEY_N)
	expect(screen.navigation_overlay.mode == 0, "third N restores the ordinary map")
	screen.world.population.agents()[0].speed = 30.0
	await key(KEY_N)
	expect(screen.navigation_overlay.reference_speed == 30.0, "diagnostic times follow the actual reference ant speed")
	await key(KEY_N)
	await key(KEY_N)
	Router.goto(&"main_menu")
	await frames(40)
	_finish()

func _check_full_map_overlay() -> void:
	var regions: Array[Rect2] = [screen.hud.get_child(0).get_global_rect(), screen.hud.task_panel.get_global_rect(), screen.hud.navigation_panel.get_global_rect(), screen.hud._bottom.get_global_rect()]
	var probes: Array[Vector2] = []
	for region in regions:
		for cell in screen.world.route_service.snapshot().walkable_cells():
			var point: Vector2 = cell_point(cell) + Vector2(-8, -8)
			if region.grow(-4).has_point(point):
				probes.append(point)
				break
	expect(probes.size() == regions.size(), "land probes cover the header, task board, legend and footer")
	var process: int = screen.world.units.process_mode
	screen.world.units.process_mode = Node.PROCESS_MODE_DISABLED
	screen.hud.hide()
	screen.navigation_overlay.mode = 0
	screen.navigation_overlay.queue_redraw()
	await frames(3)
	await RenderingServer.frame_post_draw
	var baseline: Image = get_viewport().get_texture().get_image()
	screen.navigation_overlay.mode = 1
	screen.navigation_overlay.queue_redraw()
	await frames(3)
	await RenderingServer.frame_post_draw
	var overlay: Image = get_viewport().get_texture().get_image()
	var factor: Vector2 = Vector2(overlay.get_size()) / get_viewport().get_visible_rect().size
	for point in probes:
		var a: Color = baseline.get_pixelv(Vector2i(point * factor))
		var b: Color = overlay.get_pixelv(Vector2i(point * factor))
		expect(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1, "world overlay continues underneath UI regions")
	await capture("01b-unbroken-world-overlay", 20)
	screen.hud.show()
	screen.world.units.process_mode = process
