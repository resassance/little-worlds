extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused = true; game.set_process(false); game.view.set_process(false)
	game.preferences.autosave = false
	var arguments := OS.get_cmdline_user_args()
	var path := arguments[0] if not arguments.is_empty() else "res://artifacts/population-2000-world.json"
	var speed := int(arguments[1]) if arguments.size() > 1 else 5
	if not FileAccess.file_exists(path):
		push_error("Run population_test.gd first or provide a world JSON path")
		game.queue_free(); quit(1); return
	var world := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	if world == null: game.queue_free(); quit(1); return
	game._set_world(world)
	game.view.fit_map(); game.view.zoom_by(1.25)
	for i in 160:
		game.view._process(0.016)
		await process_frame
	game.paused = false; game._set_speed(speed)
	var script_times: Array[int] = []
	var frame_times: Array[int] = []
	var view_times: Array[int] = []
	var drawing: Array[int] = []
	var last := Time.get_ticks_usec()
	var before: int = world.ticks
	for i in 600:
		if i % 100 == 20: game._request_inspection(Vector2i(world.towns[0].x, world.towns[0].y))
		if i % 100 == 80: game._set_drawer("info", false, false)
		var start := Time.get_ticks_usec()
		game._process(0.016)
		game.view._process(0.016)
		script_times.append(Time.get_ticks_usec() - start)
		if game.view.has_method("_update_people_meshes"): view_times.append(game.view.process_usec)
		await process_frame
		await RenderingServer.frame_post_draw
		if game.view.has_method("_update_people_meshes"): drawing.append(game.view.draw_usec)
		var now := Time.get_ticks_usec()
		frame_times.append(now - last); last = now
	script_times.sort(); frame_times.sort(); view_times.sort(); drawing.sort()
	print("Frames: ticks ",world.ticks-before," script p95/max ",script_times[570],"/",script_times.back()," wall p95/max ",frame_times[570],"/",frame_times.back()," render commands ",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	if not view_times.is_empty(): print("View p95/max ",view_times[570],"/",view_times.back()," draw p95/max ",drawing[570],"/",drawing.back())
	root.get_texture().get_image().save_png("res://artifacts/frame-benchmark.png")
	game.paused = true; game._finish_work()
	game.queue_free(); await process_frame
	quit()
