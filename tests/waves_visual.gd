extends "res://tests/ui_runner.gd"
## Normal-speed play through the new mode; the final hazard-removal fixture isolates its UI.
func _run() -> void:
	seed(20261108)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	expect(Router._current.controls.has(&"waves"), "spider waves have their own visible main-menu action")
	await capture("01-wave-mode-menu", 15)
	await click(Router._current.controls[&"waves"])
	await frames(15)
	screen = Router._current
	var world: World = screen.world
	var combat: CombatDirector = world.combat
	expect(combat != null and world.population.allow_warriors, "the new menu action starts the wave rules and warrior recruitment")
	await capture("02-wave-countdown", 15)
	await key(KEY_SPACE)
	var menu := Router.top_overlay() as ConstructionMenu
	expect(menu.controls.has(&"wall") and menu.controls.has(&"tower"), "the defense palette offers walls and battle towers")
	await click(menu.controls[&"tower"])
	var tower_cell := Vector2i(25, 24)
	await click_at(cell_point(tower_cell))
	await click(menu.controls[&"wall"])
	for cell in [Vector2i(27, 24), Vector2i(27, 25)]: await click_at(cell_point(cell))
	expect(menu.draft.size() == 3 and menu.draft.budget_check().allowed(), "the starting stock funds one tower and two walls")
	await capture("03-defense-plan", 20)
	await key(KEY_SPACE)
	expect(world.registry.at(tower_cell) is ConstructionSite, "non-crown defenses require actual material delivery")
	await capture("04-defense-construction", 20)
	for second in range(65):
		if world.build_controller.construction.sites.is_empty() and world.population.can_recruit(world.logistics.main_nest, AntAgent.Role.WARRIOR): break
		await frames(30)
	var tower := world.registry.at(tower_cell) as DefenseBuilding
	expect(tower != null and not tower.staffed(), "the finished tower starts disabled until it receives a warrior")
	await click_at(cell_point(world.logistics.main_nest.cell))
	var nest := Router.top_overlay() as NestMenu
	await click(nest.controls[&"residents"])
	expect(nest.controls.has(&"buy_warrior") and not nest.controls[&"buy_warrior"].disabled, "normal food production funds a warrior without a test resource grant")
	await capture("05-warrior-recruitment", 20)
	await click(nest.controls[&"buy_warrior"])
	await key(KEY_ESCAPE)
	for second in range(12):
		if tower != null and tower.staffed(): break
		await frames(30)
	expect(tower != null and tower.staffed(), "the recruited warrior automatically occupies the waiting tower")
	await click_at(cell_point(tower_cell), MOUSE_BUTTON_RIGHT)
	await capture("06-staffed-tower", 25)
	for second in range(60):
		if combat.spawner.number >= 1: break
		await frames(30)
	expect(combat.spawner.number >= 1 and not combat.spiders.is_empty(), "the real first-wave timer releases spiders")
	if not combat.spiders.is_empty():
		screen.camera.position = combat.spiders.front().global_position
		screen.camera.force_update_scroll()
	await capture("07-first-spider-wave", 30)
	var saw_combat := false
	for frame in range(1800):
		await frames(1)
		if combat.spiders.any(func(spider: SpiderAgent) -> bool: return spider.health < combat.rules.spider_health):
			saw_combat = true
			break
		if frame % 15 == 0 and not combat.spiders.is_empty():
			screen.camera.position = combat.spiders.front().global_position
			screen.camera.force_update_scroll()
	expect(saw_combat, "the staffed tower damages a naturally spawned first-wave spider")
	screen.camera.position = tower.global_position if is_instance_valid(tower) else world.map_bounds().get_center()
	screen.camera.force_update_scroll()
	await capture("08-defending-the-colony", 30)
	# Focused trap UI fixture: place the real hazard on a constructed road, without speeding simulation.
	for spider in combat.spiders.duplicate(): combat.damage(spider, 100)
	combat.spawner.remaining = 600
	var trap_cell := Vector2i(25, 26)
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"road"])
	await click_at(cell_point(trap_cell))
	await key(KEY_SPACE)
	for second in range(30):
		if world.build_controller.construction.at(trap_cell, true) == null: break
		await frames(30)
	var trap: SpiderTrap = combat.place_trap(trap_cell)
	expect(trap != null, "a spider trap can occupy the completed road")
	await click_at(cell_point(trap_cell), MOUSE_BUTTON_RIGHT)
	screen.hud.navigation_panel.refresh()
	expect(screen.hud.navigation_panel._clear_trap.visible and not screen.hud.navigation_panel._clear_trap.disabled, "right-click selects the trap and exposes removal")
	await key(KEY_SPACE)
	menu = Router.top_overlay() as ConstructionMenu
	await click(menu.controls[&"move"])
	await click_at(cell_point(trap_cell))
	expect(screen.hud.navigation_panel.inspected_cell == trap_cell, "a stationary click in construction move mode inspects the tile")
	await capture("09-persistent-trap-and-removal-cost", 20)
	await click(screen.hud.navigation_panel._clear_trap)
	expect(not combat.traps.has(trap_cell) and Router.top_overlay() == menu, "the pinned action clears the trap without closing construction")
	screen.camera.position = world.logistics.main_nest.global_position
	screen.camera.force_update_scroll()
	await click_at(cell_point(world.logistics.main_nest.cell))
	expect(Router.top_overlay() is NestMenu, "construction move mode can open the nest inspector")
	await capture("10-nest-inspector-in-construction", 20)
	await key(KEY_ESCAPE)
	expect(Router.top_overlay() == menu, "closing the nest inspector returns to the construction draft")
	await key(KEY_SPACE)
	combat.damage(world.logistics.main_nest, combat.rules.nest_health)
	await frames(15)
	var result: MenuBase = Router.top_overlay()
	expect(result != null and result.payload is MatchSummary and result.payload.reason == &"colony_destroyed", "losing the last nest opens a distinct colony-destruction defeat")
	await capture("11-colony-destroyed-result", 20)
	await click(result.controls[&"again"])
	await frames(25)
	expect(Router._current.world.combat != null and Router._current.world.combat.spiders.is_empty(), "restart preserves the selected wave mode and clears the old battle")
	Router.goto(&"main_menu")
	await frames(25)
	_finish()
