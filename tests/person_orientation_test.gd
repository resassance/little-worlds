extends SceneTree

var failures := 0
var view: WorldView

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func color_near(a: Color, b: Color) -> bool:
	return absf(a.r-b.r) < 0.015 and absf(a.g-b.g) < 0.015 and absf(a.b-b.b) < 0.015

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(960, 640)
	view = WorldView.new(); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	view.set_process(false)
	var world := WorldState.new(); world.paint(Vector2i.ZERO, 20, WorldState.Terrain.GRASS)
	world.add_person(Vector2i.ZERO, false)
	var member: Dictionary = world.people.back()
	member.born_tick = -WorldLife.YEAR * 25; member.job = "logger"
	await frame()
	view.set_world(world); view.zoom = 5.0; view.go_to_cell(Vector2i.ZERO, false)
	var source := PixelArt.person_image("logger")
	for cell in [Vector2i(0, -6), Vector2i(0, 6)]:
		member.x = cell.x; member.y = cell.y
		for facing in [-1.0, 1.0]:
			view.person_positions.clear(); view.person_directions[member.id] = facing
			view._invalidate_population_view(); view._process(0.016)
			await frame(); await frame()
			var image := root.get_texture().get_image()
			var scale_value := view.render_scales[0]
			var center: Vector2 = view.cell_to_local(cell) + Vector2(0, -4 * scale_value * view.zoom)
			for pixel in [Vector2i(7, 3), Vector2i(7, 5), Vector2i(8, 9), Vector2i(13, 5), Vector2i(6, 13)]:
				var point := center + Vector2((pixel.x+0.5-8)*facing, pixel.y+0.5-8) * scale_value * view.zoom
				var observed := image.get_pixelv(Vector2i(point))
				check(color_near(observed, source.get_pixelv(pixel)), "upright sprite at %s, facing %s, pixel %s; observed %s expected %s" % [cell, facing, pixel, observed, source.get_pixelv(pixel)])
	root.get_texture().get_image().save_png("res://artifacts/person-orientation.png")
	view.queue_free(); await process_frame
	print("Person orientation: %d failures" % failures)
	quit(1 if failures else 0)
