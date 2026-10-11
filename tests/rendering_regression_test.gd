extends SceneTree

var failures := 0
var game

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func sample(cell: Vector2i) -> Color:
	var point: Vector2 = game.view.cell_to_local(cell) - Vector2.ONE * 2 * game.view.zoom
	return root.get_texture().get_image().get_pixelv(Vector2i(point))

func close_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.015 and absf(a.g - b.g) < 0.015 and absf(a.b - b.b) < 0.015

func bake(world: WorldState, coord: Vector2i) -> void:
	var job := WorldChunkBakeJob.new(world, coord, true)
	job.advance(0)
	game.view.bake_job = job
	game.view._advance_baking()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused = true; game.set_process(false); game.view.set_process(false)
	game.preferences.autosave = false
	var world := WorldState.new()
	var cells: Array[Vector2i] = [Vector2i(10, 10), Vector2i(74, 10)]
	for cell in cells: world.paint(cell, 3, WorldState.Terrain.GRASS)
	world.climate.seasons = true; world.ticks = WorldLife.YEAR / 4
	game._set_world(world)
	game.view.zoom = 2.0; game.view.go_to_cell(Vector2i(42, 10))
	for cell in cells: bake(world, WorldState.chunk_of(cell))
	game.view._process(0.016)
	await frame(); await frame()
	var summer: Array[Color] = []
	var handles: Array[RID] = []
	for cell in cells:
		summer.append(sample(cell))
		handles.append(game.view.chunk_textures[WorldState.chunk_of(cell)].image.get_rid())
	var revision := world.revision
	for season in [2, 3, 0, 1]:
		world.ticks = season * (WorldLife.YEAR / 4)
		WorldClimate.step(world)
		game.view._process(0.016)
		await frame()
		for i in cells.size():
			var expected := summer[i]
			if season == 2: expected = expected.lerp(Color("bba776"), 0.25)
			if season == 3: expected = expected.lerp(Color("dce5dd"), 0.55)
			check(close_color(sample(cells[i]), expected), "all visible chunks change seasonal color in the same frame")
			check(game.view.chunk_textures[WorldState.chunk_of(cells[i])].image.get_rid() == handles[i], "season changes reuse existing GPU textures")
		check(world.revision == revision, "season changes do not invalidate map, navigation or sea caches")
	var coord := WorldState.chunk_of(cells[0])
	var weak: WeakRef = weakref(game.view.chunk_textures[coord].image)
	game.view.chunk_textures.erase(coord)
	check(weak.get_ref() != null, "last draw keeps evicted textures alive until commands are replaced")
	bake(world, coord)
	game.view._process(0.016); await frame()
	var stable_rid: RID = game.view.chunk_textures[coord].image.get_rid()
	for i in 60:
		world._set_terrain(cells[0], WorldState.Terrain.FOREST if i % 2 else WorldState.Terrain.GRASS)
		bake(world, coord)
		game.view.queue_redraw(); await frame()
		check(game.view.chunk_textures[coord].image.get_rid() == stable_rid, "terrain edits update the same texture resource")
		var color := sample(cells[0])
		check(not (color.r > 0.95 and color.g > 0.95 and color.b > 0.95), "repeated chunk replacements never render a white placeholder")
	check(weak.get_ref() == null, "retired textures are released after the next complete draw")
	game.view.show_minimap = true; game.view.rebuild_texture()
	for i in 300:
		game.view._advance_minimap()
		if game.view.minimap_job == null: break
	check(game.view.texture != null, "minimap finishes incrementally")
	game.queue_free(); await process_frame
	print("Rendering regression: %d failures" % failures)
	quit(1 if failures else 0)
