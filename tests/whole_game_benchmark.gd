extends SceneTree

var game
var results: Array[Dictionary] = []
var report_path := "res://artifacts/whole-game-performance.json"
var seconds := 4.0
var only := ""
var brush_radius := 16

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		if argument.begins_with("--seconds="): seconds = float(argument.trim_prefix("--seconds="))
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
		if argument.begins_with("--radius="): brush_radius = int(argument.trim_prefix("--radius="))
	call_deferred("run")

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func stats(values: Array[int]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate(); sorted.sort()
	return {"p50_ms": sorted[int((sorted.size()-1)*0.5)]/1000.0, "p95_ms": sorted[int((sorted.size()-1)*0.95)]/1000.0, "p99_ms": sorted[int((sorted.size()-1)*0.99)]/1000.0, "max_ms": sorted.back()/1000.0}

func fixture(path: String) -> WorldState:
	return WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))

func measure(name_value: String, world: WorldState, mode: String, speed_value: int = 5) -> void:
	if not only.is_empty() and not name_value.contains(only): return
	var brush_mode := mode in ["brush","brush_live"]
	game.paused = true
	game._finish_work()
	game._set_world(world)
	game._set_drawer("info", false, false)
	game._set_drawer("tools", false, false)
	game.view.show_minimap = mode == "camera"
	game.view.zoom = 1.0
	game._set_speed(speed_value)
	game.view.go_to_cell(Vector2i(500000, 0) if brush_mode else Vector2i(64,64), false)
	if mode == "cold": game.view.go_to_cell(Vector2i(500064,64),false)
	world.climate.seasons = false if brush_mode else world.climate.seasons
	for i in 50: await frame()
	world.profiling = true; world.timings.clear()
	game.paused = mode in ["paused", "brush"]
	var before := world.ticks
	var memory_before := OS.get_static_memory_usage()
	var frames: Array[int] = []
	var view: Array[int] = []
	var drawing: Array[int] = []
	var brush: Array[int] = []
	var input: Array[int] = []
	var queue_peak := 0
	var samples: Array[Dictionary] = []
	var last := Time.get_ticks_usec()
	var started := last
	var cursor := 0
	var previous := Vector2.ZERO
	if brush_mode:
		game._select_tool("grass"); game.view.brush_radius = brush_radius
		previous = game.view.cell_to_local(Vector2i(499960, -20))
		var event := InputEventScreenTouch.new(); event.position = previous; event.pressed = true
		game.view._gui_input(event)
	while Time.get_ticks_usec()-started < int(seconds*1000000):
		if brush_mode:
			var cell := Vector2i(499960 + cursor % 80, -20 + (cursor / 80) % 40)
			var next: Vector2 = game.view.cell_to_local(cell)
			var event := InputEventScreenDrag.new(); event.position = next; event.relative = next-previous
			var begin := Time.get_ticks_usec(); game.view._gui_input(event); input.append(Time.get_ticks_usec()-begin)
			previous = next
			if cursor % 8 == 0: samples.append({"cell":cell,"time":Time.get_ticks_usec(),"data":-1,"visible":-1})
		elif mode == "camera":
			game.view.go_to_cell(Vector2i(64 + int(sin(cursor*0.04)*60),64), false)
		elif mode == "cold" and cursor % 12 == 0:
			game.view.go_to_cell(Vector2i(500000+32*(cursor/12 % 40),64),false)
		elif mode == "ui" and cursor % 24 == 0:
			if cursor % 48 == 0: game._request_inspection(Vector2i(world.towns[0].x, world.towns[0].y))
			else: game._set_drawer("info", false, false)
		elif mode == "save" and cursor == 60: game._save(false)
		await frame()
		var now := Time.get_ticks_usec(); frames.append(now-last); last = now
		view.append(game.view.process_usec); drawing.append(game.view.draw_usec); brush.append(game.view.brush_usec)
		queue_peak = maxi(queue_peak,game.view.pending_tools.size())
		if brush_mode:
			var picture: Image = root.get_texture().get_image() if cursor % 8 == 0 else null
			for sample in samples:
				if sample.data < 0 and world.terrain_at(sample.cell) == WorldState.Terrain.GRASS: sample.data = now-sample.time
				if sample.visible < 0 and picture != null:
					var point: Vector2 = game.view.cell_to_local(sample.cell) + Vector2(2,2)
					if Rect2(Vector2.ZERO,Vector2(picture.get_size())).has_point(point):
						var color := picture.get_pixelv(Vector2i(point))
						if color.g > color.b and color.r > color.b: sample.visible = now-sample.time
		cursor += 1
	var elapsed := (Time.get_ticks_usec()-started)/1000000.0
	var ticks := world.ticks-before-(1 if world.stepping else 0)
	if brush_mode:
		var event := InputEventScreenTouch.new(); event.position = previous; event.pressed = false; game.view._gui_input(event)
	var tail_begin := Time.get_ticks_usec()
	while game.view.has_pending_edits() and Time.get_ticks_usec()-tail_begin < 10000000: await frame()
	var tail_ms := (Time.get_ticks_usec()-tail_begin)/1000.0
	var data: Array[int] = []; var visible: Array[int] = []; var missing := 0
	for sample in samples:
		if sample.data >= 0: data.append(int(sample.data))
		if sample.visible >= 0: visible.append(int(sample.visible))
		else: missing += 1
	var row := {"name":name_value,"seconds":elapsed,"frames":frames.size(),"frame":stats(frames),"view_cpu":stats(view),"draw_cpu":stats(drawing),"brush_cpu":stats(brush),"input_cpu":stats(input),"completed_steps_per_second":ticks/elapsed,"queue_peak":queue_peak,"tail_ms":tail_ms,"unfinished_edits":game.view.has_pending_edits(),"data_latency":stats(data),"visible_latency":stats(visible),"missing_visible_samples":missing,"samples":samples.size(),"memory_delta_bytes":OS.get_static_memory_usage()-memory_before,"timings_usec":world.timings.duplicate(),"people":world.people.size(),"towns":world.towns.size(),"regions":world.region_count(),"brush_radius":brush_radius,"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	results.append(row)
	print(JSON.stringify(row))
	game.paused = true; game._finish_work()

func run() -> void:
	root.size = Vector2i(1280,800)
	var startup := Time.get_ticks_usec()
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	var ready_ms := (Time.get_ticks_usec()-startup)/1000.0
	game.preferences.autosave = false
	var small := WorldState.new(); small.generate(42817); small.populate_demo()
	var record := JSON.stringify(small.to_dict())
	await measure("small-paused",WorldState.from_dict(JSON.parse_string(record)),"paused")
	await measure("small-x1",WorldState.from_dict(JSON.parse_string(record)),"watch",1)
	await measure("small-x5",WorldState.from_dict(JSON.parse_string(record)),"watch")
	for count in [100,500,1000]:
		if not only.is_empty() and not ("population-%d-watch" % count).contains(only): continue
		var growing := WorldState.new(); growing.generate(42817)
		var land: Array[Vector2i] = []
		for y in growing.height:
			for x in growing.width:
				if growing.walkable(Vector2i(x,y)): land.append(Vector2i(x,y))
		for i in count: growing.add_person(land[(i*13)%land.size()],false)
		for i in 21: growing.step()
		await measure("population-%d-watch" % count,growing,"watch")
	for mode in ["paused","watch","ui","camera","save"]:
		await measure("population-2000-"+mode,fixture("res://artifacts/population-2000-world.json"),mode)
	var advanced := fixture("res://tests/fixtures/advanced-46-world.json")
	await measure("advanced-x5",advanced,"watch")
	var weather := fixture("res://artifacts/population-2000-world.json")
	WorldWeather.start(weather,"rain",Vector2i(64,64),8,120)
	WorldWeather.start(weather,"frost",Vector2i(96,64),8,120)
	WorldWeather.start(weather,"drought",Vector2i(64,96),8,120)
	await measure("population-2000-weather",weather,"watch")
	if only.is_empty() or "cold-cache".contains(only):
		var cold := fixture("res://artifacts/population-2000-world.json")
		for i in 300: cold._set_terrain(Vector2i(500000+i*32,64),WorldState.Terrain.GRASS)
		cold.regions.trim(cold)
		await measure("cold-cache",cold,"cold")
	await measure("continuous-brush",fixture("res://artifacts/population-2000-world.json"),"brush")
	await measure("continuous-brush-x5",fixture("res://artifacts/population-2000-world.json"),"brush_live")
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"scene_ready_ms":ready_ms,"renderer":RenderingServer.get_video_adapter_name(),"viewport":[1280,800],"results":results}
	var file := FileAccess.open(report_path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	game.queue_free(); await frame(); quit()
