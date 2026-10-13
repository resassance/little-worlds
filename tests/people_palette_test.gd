extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func close_color(a: Color, b: Color) -> bool:
	return absf(a.r-b.r) < 0.015 and absf(a.g-b.g) < 0.015 and absf(a.b-b.b) < 0.015

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(960,640)
	var world := WorldState.new(); world.paint(Vector2i.ZERO, 24, WorldState.Terrain.GRASS)
	var candidate := 1
	for palette in PixelArt.PEOPLE_PALETTES:
		while PixelArt.person_palette(world.world_seed, candidate) != palette: candidate += 1
		world.next_id = candidate
		world.add_person(Vector2i((palette%6)*3-7,(palette/6)*4-6), false)
		candidate += 1
	var saved := JSON.stringify(world.to_dict())
	var view := WorldView.new(); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	await frame()
	view.set_world(world); view.zoom = 4.0; view.go_to_cell(Vector2i.ZERO,false)
	for i in 8: view._process(0.016); await frame()
	var screenshot := root.get_texture().get_image()
	for i in world.people.size():
		var member: Dictionary = world.people[i]
		var scale_value := view.render_scales[i]
		var point := view.cell_to_local(Vector2i(member.x,member.y)) + Vector2(-0.5,-6.5) * scale_value * view.zoom
		check(close_color(screenshot.get_pixelv(Vector2i(point)), PixelArt.SKIN_TONES[i/6]), "rendered skin remains inside its assigned palette row")
	check(view.people_multimesh.visible_instance_count == 24, "all color combinations share the existing people mesh")
	check(view.people_atlas.get_width()<=2048 and view.people_atlas.get_height()<=2048, "palette atlas fits conservative mobile texture limits")
	check(JSON.stringify(world.to_dict()) == saved, "colors do not alter simulation or its random streams")
	screenshot.save_png("res://artifacts/people-palettes.png")
	var loaded := WorldState.from_dict(JSON.parse_string(saved))
	check(loaded != null, "palette fixture survives JSON save/load")
	if loaded != null:
		for i in world.people.size(): check(PixelArt.person_palette(loaded.world_seed,loaded.people[i].id)==PixelArt.person_palette(world.world_seed,world.people[i].id), "loading preserves individual colors")
	view.queue_free(); await process_frame
	print("People palettes: %d failures" % failures)
	quit(1 if failures else 0)
