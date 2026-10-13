extends SceneTree

var failures := 0

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error("FAIL: "+label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.paused = true; game.preferences.autosave = false
	var source := FileAccess.get_file_as_string("res://artifacts/population-2000-world.json")
	var samples: Array[int] = []
	for cycle in 12:
		var world := WorldState.from_dict(JSON.parse_string(source))
		check(world != null,"repeated world load succeeds")
		game._set_world(world); world = null
		for i in 80:
			await process_frame; await RenderingServer.frame_post_draw
		check(game.world.population.ready,"paused world builds its spatial index in bounded portions")
		check(game.view.pending_tools.is_empty() and game.view.brush_previews.is_empty(),"world switches leave no old editing state")
		samples.append(OS.get_static_memory_usage())
	check(samples.back()-samples[2] < 8*1024*1024,"repeated identical worlds do not accumulate model and render resources")
	print("World stability: memory samples ",samples,"; failures ",failures)
	game.queue_free(); await process_frame
	quit(1 if failures else 0)
