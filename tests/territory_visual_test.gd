extends "res://tests/territory_test.gd"

var game

func settle_view() -> void:
	for i in 45: await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	settlement.name = "Медный берег"
	master(world,settlement,"carpentry")
	var member := start_work(world,settlement,"forest",Vector2i(-6,0),Vector2i(-6,0))
	for i in 14:
		world.ticks += 1; WorldEconomy.execute(world,member,settlement)
	check(settlement.landworks.project.work>0 and not settlement.landworks.project.ready,"visual fixture shows work in progress")
	var file := FileAccess.open("res://artifacts/territory-world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(world.to_dict())); file.close()
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.paused = true; game.preferences.autosave = false
	game._set_world(world); game.status_panel.hide()
	for screen in [[Vector2i(1440,900),1.0],[Vector2i(2160,1080),2.25],[Vector2i(1080,2400),3.0]]:
		root.size = screen[0]; game.touch_ui = screen[1]>1.0; game.inspector.touch_ui = game.touch_ui
		game.system_ui_scale = screen[1]; game.preferences.ui_scale = 1.0
		game._apply_ui_scale(); game._build_theme()
		if game.touch_ui: game._prepare_touch_ui(game)
		game._responsive(); game.view.zoom = 3.0
		game.view.go_to_cell(Vector2i(-5,0),false)
		game.selected_cell = WorldState.NO_CELL; game.inspected_person_id = -1
		game._inspect(Vector2i.ZERO); game._set_drawer("info",true,false)
		game.inspector.set_expanded("landworks",true)
		var before := JSON.stringify(world.to_dict())
		game._refresh_inspector()
		await settle_view()
		game.history_scroll.ensure_control_visible(game.inspector.sections.landworks.body)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		check(game.inspector.readable_text().contains("Посадка леса") and game.inspector.readable_text().contains("работа"),"inspector shows real land work and progress")
		check(before==JSON.stringify(world.to_dict()),"new inspector details do not mutate the world")
		check(Rect2(Vector2.ZERO,game.size).encloses(game.sidebar.get_global_rect()),"land work inspector fits the screen")
		check(game.history_scroll.get_h_scroll_bar().max_value<=game.history_scroll.size.x+1,"land work details fit without horizontal scroll")
		if game.touch_ui: check(game.inspector.sections.landworks.button.custom_minimum_size.y*game.ui_scale/game.system_ui_scale>=47.9,"new accordion keeps a 48 dp mobile touch area")
		root.get_texture().get_image().save_png("res://artifacts/territory-%dx%d.png" % [screen[0].x,screen[0].y])
	game.queue_free(); await process_frame
	print("Territory visuals: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
