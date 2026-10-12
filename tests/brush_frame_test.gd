extends SceneTree

var failures := 0
var game
var graphical := false
var input_times: Array[int] = []
var script_times: Array[int] = []
var draw_times: Array[int] = []
var main_times: Array[int] = []
var view_times: Array[int] = []

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: "+description)

func frame() -> void:
	await process_frame
	if graphical: await RenderingServer.frame_post_draw

func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new(); event.position = point; event.pressed = pressed
	var start := Time.get_ticks_usec(); game.view._gui_input(event)
	input_times.append(Time.get_ticks_usec()-start)

func drag(from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new(); event.position = to; event.relative = to-from
	var start := Time.get_ticks_usec(); game.view._gui_input(event)
	input_times.append(Time.get_ticks_usec()-start)

func tick() -> void:
	var start := Time.get_ticks_usec()
	game._process(0.016)
	main_times.append(Time.get_ticks_usec()-start)
	game.view._process(0.016)
	view_times.append(game.view.process_usec)
	script_times.append(Time.get_ticks_usec()-start)
	await frame()
	draw_times.append(game.view.draw_usec)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	root.size = Vector2i(2160,1080)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.view.set_process(false); game.preferences.autosave = false
	game.system_ui_scale = 2.25; game._apply_ui_scale()
	var world := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/population-2000-world.json")))
	check(world != null,"large gameplay fixture loads")
	if world == null: quit(1); return
	game._set_world(world); game.view.zoom = 1.0; game.view.go_to_cell(Vector2i(64,64),false)
	game.paused = false; game._set_speed(5)
	for i in 80: game.view._process(0.016); await frame()
	for mode in ["grass","forest","biome_2","fire","rain","mountain","water"]:
		var phase_first := script_times.size()
		game.view.cancel_input(); game._select_tool(mode); game.view.brush_radius = 64 if mode not in ["fire","rain"] else 8
		var previous: Vector2 = game.view.cell_to_local(Vector2i(160,64))
		touch(previous,true)
		for i in 20:
			var next: Vector2 = game.view.cell_to_local(Vector2i(160+i,64+i/3))
			drag(previous,next); previous = next
			if i == 8:
				game._toggle_pause(); check(game.paused,"pause responds during an unfinished large stroke")
			if i == 9: game._toggle_pause(); check(not game.paused,"play resumes during an unfinished large stroke")
			await tick()
		touch(previous,false)
		var frames := 0
		while game.view.has_pending_edits() and frames < 600:
			await tick(); frames += 1
		check(not game.view.has_pending_edits(),"queued "+mode+" stroke finishes without losing input")
		print("Brush phase ",mode," main/view peaks ",main_times.slice(phase_first).max(),"/",view_times.slice(phase_first).max()," us")
		if graphical and mode in ["forest","fire","rain"]:
			for i in 100: game.view._process(0.016); await frame()
			root.get_texture().get_image().save_png("res://artifacts/brush-"+mode+".png")
	var before: int = world.ticks
	for i in 100: await tick()
	check(world.ticks > before,"simulation advances after strokes at x5")
	game.paused = true; game._finish_work()
	check(WorldAudit.conserved(world),"all tools under gameplay preserve resource accounting")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict(),"",true,true))) != null,"world remains loadable after all tools under gameplay")
	input_times.sort(); script_times.sort(); draw_times.sort()
	check(input_times.back() < 16000,"touch input never performs a full brush stamp")
	check(script_times[int(script_times.size()*.95)] < 16000,"regular brush and gameplay processing stay within one CPU frame in this fixture")
	check(script_times.back() < 33000,"brush processing has no stall longer than two 60-Hz frames in this fixture")
	print("Brush frames: input p95/max %.2f/%.2f ms; script p95/max %.2f/%.2f ms; draw p95/max %.2f/%.2f ms; failures %d" % [input_times[int(input_times.size()*.95)]/1000.0,input_times.back()/1000.0,script_times[int(script_times.size()*.95)]/1000.0,script_times.back()/1000.0,draw_times[int(draw_times.size()*.95)]/1000.0,draw_times.back()/1000.0,failures])
	game.queue_free(); await frame(); quit(1 if failures else 0)
