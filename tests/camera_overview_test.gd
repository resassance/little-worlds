extends SceneTree

var failures := 0
var game

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func land_visible(cell: Vector2i) -> bool:
	var position: Vector2 = game.view.cell_to_local(cell)
	var color := root.get_texture().get_image().get_pixelv(Vector2i(position))
	return color.g > color.b and color.r > WorldView.COLORS[0].r + 0.15

func warm(cell: Vector2i, zoom: float) -> void:
	game.view.zoom = zoom
	game.view.go_to_cell(cell, false)
	for i in 160:
		game.view._process(0.016)
		await frame()
		if i > 3 and land_visible(cell): return

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused = true; game.preferences.autosave = false
	game.set_process(false); game.view.set_process(false)
	game.view.show_minimap = false
	var original := WorldState.new()
	var cells: Array[Vector2i] = [Vector2i(16, 16), Vector2i(-80, -48), Vector2i(100016, -60016)]
	for cell in cells: original.paint(cell, 12, WorldState.Terrain.GRASS)
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(original.to_dict(), "", true, true)))
	check(loaded != null and loaded.region_bounds == original.region_bounds, "loaded world restores the land catalogue without fitting the camera or showing a minimap")
	if loaded == null: game.queue_free(); quit(1); return
	game._set_world(loaded)
	for cell in cells:
		for zoom in [1.0, 0.51, 0.49, 0.2, 0.08, 0.01, 0.001]:
			await warm(cell, zoom)
			check(land_visible(cell), "loaded land remains visible at zoom %.3f at %s" % [zoom, cell])
	await warm(cells[0], 1.0)
	game.view.overview_textures.clear()
	game.view.bake_job = null; game.view.bake_queue.clear(); game.view.bake_pending.clear()
	game.view.zoom = 0.49; game.view.go_to_cell(cells[0], false)
	await frame()
	check(land_visible(cells[0]), "switching to overview retains detailed land while coarse textures are prepared")
	var path := "user://camera-overview-test.json"
	check(SaveStore.save_world(original, path) == OK, "regional camera fixture saves")
	var regional := SaveStore.load_world(path)
	check(regional != null and regional.region_bounds == original.region_bounds, "regional files restore overview land bounds before any camera query")
	if regional != null:
		game._set_world(regional)
		await warm(cells[0], 0.2)
		check(land_visible(cells[0]), "regional save starts with visible land in overview")
	game.queue_free(); await frame()
	print("Camera overview: %d failures" % failures)
	quit(1 if failures else 0)
