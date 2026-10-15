extends SceneTree

var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in 6: await process_frame
	await create_timer(0.05).timeout
	await RenderingServer.frame_post_draw

func inspect_home(home: Dictionary) -> void:
	game.selected_cell = WorldState.NO_CELL
	game.inspected_person_id = -1
	game._inspect(Vector2i(home.x, home.y))
	game._set_drawer("info", true, false)

func refresh_details(key: String, opened: bool = true) -> void:
	game.inspector.sections[key].button.button_pressed = opened
	game._refresh_inspector()

func node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += node_count(child)
	return count

func capture(name_value: String) -> void:
	game.status_panel.hide()
	await settle()
	root.get_texture().get_image().save_png("res://artifacts/inspector-" + name_value + ".png")

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused = true
	game.preferences.autosave = false
	var world := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))
	check(world != null, "advanced settlement fixture loads")
	game._set_world(world)
	var home: Dictionary = world.towns[0]
	game.view.go_to_cell(Vector2i(home.x, home.y), false)
	game.view.zoom = 2.0
	var before := JSON.stringify(world.to_dict())
	inspect_home(home)
	await settle()
	var inspector: WorldInspector = game.inspector
	check(inspector.title_label.text == home.name, "settlement name is the primary heading")
	check(inspector.metric_nodes[0].value.text == str(WorldEconomy.members(world, home).size()), "population card uses actual residents")
	check(inspector.metric_nodes[1].value.text.ends_with(str(WorldEconomy.housing(world, home))), "housing card uses actual capacity")
	check(inspector.metric_nodes[2].value.text.contains("мес."), "food card shows months of supplies")
	check(not game.world_info.visible and game.history_box.get_child_count() == 0, "world history is absent from selection overview")
	check(inspector.detail_updates == 0, "collapsed details are not computed")
	for section in inspector.sections.values():
		check(not section.body.visible and section.body.get_child_count() == 0, "details start closed and unallocated")
	await capture("settlement-desktop")
	refresh_details("development")
	check(inspector.readable_text().contains("Строительство и инженерия"), "development has distinct domain headings")
	refresh_details("technology")
	check(inspector.readable_text().contains("Хранение пищи: Применяется"), "technology lists actual application state")
	refresh_details("economy")
	check(inspector.readable_text().contains("Архив: 1"), "economy exposes actual infrastructure")
	refresh_details("population")
	refresh_details("sea")
	refresh_details("terrain")
	check(inspector.readable_text().contains("Возраст"), "population includes age distribution")
	check(inspector.readable_text().contains("Встреч:"), "maritime section includes established contacts")
	check(inspector.readable_text().contains("Координаты"), "terrain has a separate coordinate row")
	var nodes := node_count(inspector)
	var times: Array[int] = []
	for i in 40:
		var started := Time.get_ticks_usec()
		game._refresh_inspector()
		times.append(Time.get_ticks_usec() - started)
	check(node_count(inspector) == nodes, "refresh reuses existing detail controls")
	check(inspector.expanded("technology"), "simulation refresh preserves expanded sections")
	check(JSON.stringify(world.to_dict()) == before, "inspector does not alter simulation or saved state")
	times.sort()
	print("Inspector expanded refresh p95: %.3f ms, max %.3f ms" % [times[38] / 1000.0, times.back() / 1000.0])
	game.history_scroll.scroll_vertical = 100
	await settle()
	var scroll: int = game.history_scroll.scroll_vertical
	game._set_info_tab(true)
	game._refresh_inspector()
	await settle()
	check(not inspector.visible and game.world_info.visible, "world tab separates global history")
	check(game.history_box.get_child_count() > 0, "history builds when requested")
	await capture("events-desktop")
	game._set_info_tab(false)
	await settle()
	check(game.history_scroll.scroll_vertical == scroll, "switching tabs preserves selection scroll")
	for key in inspector.sections: refresh_details(key, false)
	var updates := inspector.detail_updates
	game._refresh_inspector()
	check(inspector.detail_updates == updates, "closed sections stay uncomputed after use")
	var food: int = home.food
	home.food = 0
	game._refresh_inspector()
	check(inspector.metric_nodes[2].value.get_theme_color("font_color") == WorldInspector.ALERT, "food shortage has visible warning color")
	home.food = food
	game._refresh_inspector()
	for screen in [[Vector2i(2160,1080),2.25], [Vector2i(1920,1080),3.0], [Vector2i(2400,1080),3.0], [Vector2i(1080,2400),3.0], [Vector2i(1180,820),2.0]]:
		root.size = screen[0]
		game.touch_ui = true
		inspector.touch_ui = true
		game.system_ui_scale = screen[1]
		game.preferences.ui_scale = 1.0
		game._apply_ui_scale()
		game._build_theme()
		game._prepare_touch_ui(game)
		game._responsive()
		inspect_home(home)
		await settle()
		check(Rect2(Vector2.ZERO, game.size).encloses(game.sidebar.get_global_rect()), "phone inspector fits " + str(screen[0]))
		for section in inspector.sections.values():
			check(section.button.custom_minimum_size.y * game.ui_scale / game.system_ui_scale >= 47.9, "section touch area is at least 48 dp")
		for item in inspector.metric_nodes:
			var rect: Rect2 = item.card.get_global_rect()
			check(rect.position.x >= game.sidebar.position.x and rect.end.x <= game.sidebar.get_global_rect().end.x, "metric fits panel width")
		refresh_details("technology")
		await settle()
		var bar: VScrollBar = game.history_scroll.get_v_scroll_bar()
		game.history_scroll.scroll_vertical = int(bar.max_value)
		await settle()
		check(game.history_scroll.scroll_vertical > 0, "long details can be scrolled on phone")
		check(game.history_scroll.get_h_scroll_bar().max_value <= game.history_scroll.size.x + 1, "no horizontal overflow on phone")
		refresh_details("technology", false)
		game.history_scroll.scroll_vertical = 0
		if screen[0] == Vector2i(2160,1080):
			await capture("settlement-phone")
			check(inspector.metric_nodes[3].card.get_global_rect().end.y <= game.history_scroll.get_global_rect().end.y, "four summary cards fit 2160x1080 at 2.25 density")
			refresh_details("development")
			await settle()
			game.history_scroll.scroll_vertical = 220
			await capture("development-phone")
			refresh_details("development", false)
	game.system_ui_scale = 2.25
	root.size = Vector2i(2160, 1080)
	game._apply_ui_scale()
	game._prepare_touch_ui(game)
	game._responsive()
	var original_name: String = home.name
	home.name = "Поселение с очень длинным именем на дальнем северном берегу"
	game._refresh_inspector()
	await settle()
	check(inspector.title_label.size.x <= game.sidebar.size.x - 28, "long settlement name wraps inside panel")
	home.name = original_name
	game._set_info_tab(true)
	game._refresh_inspector()
	game.history_scroll.scroll_vertical = 150
	game._inspect(Vector2i(world.towns[1].x, world.towns[1].y))
	await settle()
	check(not game.info_world and game.history_scroll.scroll_vertical == 0, "new selection from history opens at top")
	var person: Dictionary = world.people[0]
	game.inspected_person_id = person.id
	game._inspect(Vector2i(person.x, person.y), false)
	check(inspector.selection_kind == "person" and inspector.title_label.text.contains(person.name), "person has own primary heading")
	check(not inspector.sections.economy.box.visible and inspector.sections.family.box.visible, "person shows relevant sections only")
	check(not inspector.expanded("family"), "new selection starts with concise overview")
	refresh_details("family")
	refresh_details("skills")
	refresh_details("relations")
	check(inspector.readable_text().contains("Поколение"), "family details are preserved")
	check(inspector.readable_text().contains("Предпочтение"), "skills retain personal vocation")
	await capture("resident-phone")
	var cell := Vector2i(-900000, -900000)
	game._inspect(cell)
	check(inspector.selection_kind == "terrain" and inspector.subtitle_label.text.contains("-900000"), "remote tile has compact coordinate card")
	check(not inspector.metric_nodes[2].card.visible, "tile omits irrelevant resident statistics")
	game._set_drawer("info", false, false)
	updates = game.inspector_updates
	for i in 3: world.step()
	await settle()
	check(game.inspector_updates == updates, "hidden panel does not refresh")
	game.queue_free()
	for i in 3: await process_frame
	print("Inspector UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
