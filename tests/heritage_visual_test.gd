extends SceneTree

var failures := 0
var game

func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func _initialize() -> void:
	call_deferred("run")

func ready_frame() -> void:
	for i in 45: await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused = true; game.preferences.autosave = false
	var world := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))
	var home: Dictionary = world.towns[0]
	for i in range(world.people.size()-1,-1,-1):
		if world.people[i].home == home.id: world.remove_person(i,"пожар")
	for month in 2:
		world.ticks += WorldEconomy.DAY_TICKS
		var job := WorldHeritageJob.new(world)
		while not job.finished: job.unit()
	world._repair_buildings()
	game._set_world(world)
	game.view.zoom = 3.2
	game.view.go_to_cell(Vector2i(76,71),false)
	game._inspect(Vector2i(home.x,home.y))
	game.inspector.set_expanded("history",true)
	game._refresh_inspector()
	game.status_panel.hide()
	await ready_frame()
	check(game.inspector.title_label.text == home.name,"ruin inspector identifies the real former settlement")
	check(game.inspector.readable_text().contains("пожар"),"history shows the recorded loss rather than an invented cause")
	check(game.view.landscape_textures.size() > 0,"ruins are baked through the budgeted terrain overlay")
	root.get_texture().get_image().save_png("res://artifacts/heritage-desktop.png")
	for screen in [[Vector2i(2160,1080),2.25],[Vector2i(1080,2400),3.0]]:
		root.size = screen[0]
		game.touch_ui = true; game.inspector.touch_ui = true
		game.system_ui_scale = screen[1]; game.preferences.ui_scale = 1.0
		game._apply_ui_scale(); game._build_theme(); game._prepare_touch_ui(game); game._responsive()
		game.view.go_to_cell(Vector2i(76,71),false)
		game._inspect(Vector2i(home.x,home.y))
		game.inspector.set_expanded("history",true); game._refresh_inspector()
		await ready_frame()
		var bounds: Rect2 = game.inspector.get_global_rect()
		check(bounds.size.x <= game.history_scroll.size.x,"history card fits the scroll viewport on phone")
		check(game.inspector.sections.history.button.size.y >= game._touch_target(),"history control respects mobile touch size")
		root.get_texture().get_image().save_png("res://artifacts/heritage-%dx%d.png" % [screen[0].x,screen[0].y])
	game.queue_free(); await process_frame
	print("Heritage visual: ",failures," failures")
	quit(1 if failures else 0)
