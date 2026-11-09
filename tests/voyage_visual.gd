extends "res://tests/ui_runner.gd"
## Gameplay runs at recorded speed. Progression setup supplies stock and tasks only.
func _run() -> void:
	seed(8123)
	AppSettings.reset_defaults()
	get_viewport().add_child(load("res://boot.tscn").instantiate())
	await frames(35)
	await click(Router._current.controls[&"maps"])
	await frames(10)
	var editor: Control = Router._current
	editor._generator_seed.value = 8123
	editor._generator_size.select(0)
	await frames(6)
	await click(_button(editor, "ui.voyage.generate"))
	expect(editor._map.get_used_cells().size() == 2500 and editor._dirty, "generator controls produce an editable 50 by 50 seeded archipelago")
	await capture("01-generator-and-islands", 35)
	editor._camera.set_level(WorldCamera.MIN_LEVEL)
	editor._camera.position.y -= 80
	await capture("01b-whole-generated-archipelago", 35)
	editor._title.text = "Пробный архипелаг"
	await click(_button(editor, "ui.map.save"))
	var filename: String = editor._saved.get_selected_metadata()
	expect(not filename.is_empty(), "the generated layout saves as an ordinary editable map")
	_choose_map(editor._starting_maps[0], "builtin/tidal_shards")
	_choose_map(editor._starting_maps[1], filename)
	expect(LevelStore.starting_level(false) == "builtin/tidal_shards" and LevelStore.starting_level(true) == filename, "normal and waves starting maps are saved separately")
	await capture("01c-starting-maps", 35)
	await click(_button(editor, "ui.common.main_menu"))
	await frames(25)
	await click(Router._current.controls[&"play"])
	await frames(30)
	expect(Router._current.world.map_size == Vector2i(136, 84) and Router._current.world.combat == null, "Play opens the selected standard map")
	Router.goto(&"main_menu")
	await frames(30)
	await click(Router._current.controls[&"waves"])
	await frames(30)
	screen = Router._current
	var world: World = screen.world
	expect(world.map_size == Vector2i(50, 50) and world.combat != null, "Spider waves opens the saved custom map with combat enabled")
	world.combat.spawner.remaining = 500
	world.match_controller.add_time(600)
	for type in world.inventory.registered_types(): world.inventory.add(type, 10000)
	var home: House = world.logistics.main_nest
	screen.camera.position = home.global_position + Vector2(20, 0)
	screen.camera.set_level(3)
	expect(world.population.recruit(home, AntAgent.Role.WARRIOR), "player can recruit a configured warrior")
	var warrior: AntAgent = world.population.agents().filter(func(ant: AntAgent): return ant.role == AntAgent.Role.WARRIOR)[0]
	warrior.needs.configure(60)
	await frames(100)
	expect(warrior.status == AntAgent.Status.WALKING and warrior._destination == &"combat_patrol", "full warrior with capacity sixty patrols actual points of interest")
	await capture("02-warrior-patrol", 60)
	# Adjacent road sites demonstrate the corrected independent site markers.
	for offset in [Vector2i(-1, 1), Vector2i(-2, 1), Vector2i(-3, 1)]:
		world.build_controller.try_build(load("res://game/building/options/road.tres"), home.cell + offset)
	await capture("03-construction-markers", 35)
	for step in range(5):
		var index := 0
		while world.tasks.slots[index] == null: index += 1
		world.tasks.submit(index)
	await frames(5)
	expect(get_tree().paused and screen.campaign_panel.visible, "three reward choices pause the simulation")
	await capture("04-choose-one-reward", 50)
	await click(screen.campaign_panel.controls[2])
	expect(not world.tasks.pending_reward and world.tasks.level == 2, "choosing one reward resumes the game at the next stage")
	for stage in range(3):
		for step in range(5):
			var index := 0
			while world.tasks.slots[index] == null: index += 1
			world.tasks.submit(index)
		await frames(4)
		await click(screen.campaign_panel.controls[stage % 3])
	expect(world.tasks.level == 5 and world.build_controller.options.has(Voyage.SHIP), "ship appears after reaching development level five")
	# A real ship order: ants transport paid materials and perform its assembly.
	var ship_cell: Vector2i = _nearest_ship_cell(world, home.cell)
	expect(world.build_controller.try_build(Voyage.SHIP, ship_cell), "ship order accepts a funded coastal water tile")
	screen.camera.position = world.route_service.cell_to_world(ship_cell)
	screen.camera.force_update_scroll()
	await frames(4)
	var requests: TaskPanel = screen.hud.task_panel
	var scroll := requests.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	expect(bar.visible and bar.size.x <= 6, "task scrolling uses a narrow visible thumb")
	expect(bar.get_global_rect().position.x - requests._content.get_global_rect().end.x >= 4, "task text and buttons have a separate scrollbar gutter")
	await capture("05-ship-material-delivery", 50)
	await key(KEY_ESCAPE)
	await click(Router.top_overlay().controls[&"save"])
	expect(Router.top_overlay().controls[&"save"].text == "ui.voyage.saved", "pause menu confirms a saved game")
	await capture("06-save-game", 30)
	await click(Router.top_overlay().controls[&"main"])
	await frames(25)
	expect(Router._current.controls.has(&"continue"), "saved game exposes Continue in the main menu")
	await capture("07-continue-menu", 25)
	await click(Router._current.controls[&"continue"])
	await frames(30)
	screen = Router._current
	world = screen.world
	expect(world.tasks.level == 5 and world.build_controller.construction.at(ship_cell) != null, "Continue restores the ship site and development stage")
	screen.camera.position = world.route_service.cell_to_world(ship_cell)
	screen.camera.set_level(3)
	for second in range(210):
		if world.voyage.departed: break
		await frames(30)
	expect(world.voyage.departed and screen.campaign_panel.visible, "workers physically complete the ship and show scored victory")
	for index in range(3):
		expect(screen.campaign_panel.controls[index].icon != null, "the victory screen has a real preview for each destination")
	await capture("08-victory-and-three-islands", 60)
	var previous_stock: Dictionary = world.voyage.wealth()
	await click(screen.campaign_panel.controls[1])
	await frames(35)
	screen = Router._current
	world = screen.world
	expect(world.voyage.island == 2 and world.tasks.buffs.size() == 4, "destination choice begins a harder second island with four retained upgrades")
	expect(world.inventory.quantity(world.inventory.type_by_id(&"wood")) >= int(previous_stock.wood), "new island keeps the colony stock")
	await capture("09-next-island-kept-upgrades", 60)
	Router.goto(&"main_menu")
	await frames(35)
	_finish()

func _button(root: Node, text: String) -> Button:
	for child in root.find_children("*", "Button", true, false):
		if child.text == text: return child
	return null


func _choose_map(choice: OptionButton, filename: String) -> void:
	for index in range(choice.item_count):
		if choice.get_item_metadata(index) == filename:
			choice.select(index)
			choice.item_selected.emit(index)
			return

func _nearest_ship_cell(world: World, origin: Vector2i) -> Vector2i:
	var map: TerrainMap = world.get_node("Map")
	var best := Vector2i(-1, -1)
	var distance := INF
	var field: NavigationField = world.route_service.reverse_field([origin])
	for cell in map.get_used_cells():
		if map.surface_at(cell).kind != TerrainType.Kind.WATER:
			continue
		if not world.build_controller.placement_check(Voyage.SHIP, cell).allowed():
			continue
		for shore in Voyage.SHIP.entries_at(cell):
			var cost: float = field.cost(shore)
			if cost < distance:
				distance = cost
				best = cell
	return best
