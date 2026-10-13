extends SceneTree

var view: WorldView
var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(1280, 800)
	view = WorldView.new(); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	await frame()
	var world := WorldState.new(); world.generate(42817); world.populate_demo()
	world.weather.rate = 0
	for i in 400: world.step()
	view.set_world(world); view.zoom = 2.0; view.focus_island(); view.zoom = 2.0
	var center := Vector2i(world.towns[0].x, world.towns[0].y)
	view.go_to_cell(center, false)
	for kind in ["rain", "drought", "frost", "thunder", "storm"]:
		world.weather.active.clear()
		var event := WorldWeather.start(world, kind, center, 10, 30)
		world.changed.emit()
		var before := JSON.stringify(world.to_dict())
		for i in 10: view._process(0.016); await frame()
		check(view.people_multimesh.visible_instance_count > 0, "weather keeps real residents visible")
		check(JSON.stringify(world.to_dict()) == before, "weather rendering does not advance simulation")
		root.get_texture().get_image().save_png("res://artifacts/weather-" + kind + ".png")
		view.go_to_cell(Vector2i(500000, -500000), false)
		var chunks := world.region_count()
		for i in 4: view._process(0.016); await frame()
		check(world.region_count() == chunks, "weather display does not create remote terrain")
		view.go_to_cell(center, false)
	view.queue_free(); await process_frame
	print("Weather rendering: %d failures" % failures)
	quit(1 if failures else 0)
