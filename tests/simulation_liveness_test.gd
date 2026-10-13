extends SceneTree

var game
var duration_usec := 90000000

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="): duration_usec = maxi(1000000,int(float(argument.trim_prefix("--seconds="))*1000000))
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.preferences.autosave = true
	game._set_speed(5)
	var world := WorldState.new()
	world.generate(42817)
	world.populate_demo()
	if "--large-world" in OS.get_cmdline_user_args():
		world = WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))
		for i in 1000: world._set_terrain(Vector2i(100000+i*32,0),WorldState.Terrain.GRASS)
		world.regions.trim(world)
	game._set_world(world)
	if "--autosave-soon" in OS.get_cmdline_user_args(): game.autosave_timer = 59.8
	game.paused = false
	var start := Time.get_ticks_usec()
	var progress := start
	var ticks := world.ticks
	var saves := 0
	var had_save := false
	var maximum_gap := 0
	var capture_start := 0
	var captures: Array[int] = []
	while Time.get_ticks_usec() - start < duration_usec:
		await process_frame
		if world.ticks != ticks:
			maximum_gap = maxi(maximum_gap,Time.get_ticks_usec()-progress)
			ticks = world.ticks
			progress = Time.get_ticks_usec()
		if game.save_job != null:
			if not had_save: capture_start = Time.get_ticks_usec()
			had_save = true
			if capture_start > 0 and game.save_job.snapshot_ready:
				captures.append(Time.get_ticks_usec()-capture_start); capture_start = 0
		elif had_save:
			saves += 1
			had_save = false
			print("SAVE completed ", saves, " at tick ", ticks)
		if Time.get_ticks_usec() - progress > 3000000:
			print("STALLED tick=", ticks, " step=", game.step_job.phase if game.step_job != null else -1, " cursor=", game.step_job.cursor if game.step_job != null else -1, " units=", game.step_job.units if game.step_job != null else -1, " save=", game.save_job.phase if game.save_job != null else -1, " failed=", world.regions.failed, " pending=", game.view.has_pending_edits(), " modal=", game._modal_open(), " paused=", game.paused)
			quit(1)
			return
	print("Liveness: ticks=", ticks, " saves=", saves, " people=", world.people.size(), " largest_gap_ms=",maximum_gap/1000.0," captures_usec=",captures)
	game.paused = true
	game._finish_work()
	game.queue_free()
	await process_frame
	quit(0 if saves > 0 else 1)
