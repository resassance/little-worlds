extends SceneTree

var failures := 0

func check(value: bool, description: String) -> void:
	if not value: failures += 1; push_error("FAIL: "+description)

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	var world := WorldState.new()
	world.paint(Vector2i.ZERO,8,WorldState.Terrain.GRASS)
	var home := {"id":1,"x":0,"y":0}
	var nav := WorldEconomy.navigation(world,home)
	world._set_terrain(Vector2i(500000,0),WorldState.Terrain.GRASS)
	check(is_same(nav,world.navigation[1]),"remote new land preserves an unrelated navigation cache")
	world._set_terrain(Vector2i(1,0),WorldState.Terrain.MOUNTAIN)
	check(not world.navigation.has(1),"local obstacles invalidate affected navigation")
	var restored_nav := WorldEconomy.navigation(world,home)
	check(not restored_nav.parents.has(Vector2i(1,0)),"rebuilt navigation excludes the new obstacle")
	var route := WorldTravelPathJob.new(world,Vector2i(-4,0),Vector2i(4,0))
	route.advance(0)
	world._set_terrain(Vector2i(0,2),WorldState.Terrain.FOREST)
	var same_route := WorldTravelPathJob.new(world,Vector2i(-4,0),Vector2i(4,0))
	check(same_route.finished and same_route.result == route.result,"forest changes preserve valid land route caches")
	world._set_terrain(Vector2i(0,2),WorldState.Terrain.MOUNTAIN)
	var changed_route := WorldTravelPathJob.new(world,Vector2i(-4,0),Vector2i(4,0))
	check(not changed_route.finished,"new obstacles invalidate land route caches")
	var inhabited := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/population-2000-world.json")))
	check(not WorldTerrainRepairJob.needed(inhabited,{Vector2i(15000,0):true}),"distant empty terrain needs no population reconciliation")
	var resident: Dictionary = inhabited.people[0]
	check(WorldTerrainRepairJob.needed(inhabited,{WorldState.chunk_of(Vector2i(resident.x,resident.y)):true}),"inhabited terrain keeps population reconciliation")
	var view := WorldView.new(); root.add_child(view); view.set_process(false)
	var empty := WorldState.new(); view.set_world(empty)
	var expected := {}
	var points: Array[Vector2i] = [Vector2i(-24,-12),Vector2i(-12,-6),Vector2i.ZERO,Vector2i(12,6),Vector2i(12,-6),Vector2i(-12,-6)]
	view.tool = "grass"; view.brush_radius = 2
	for i in range(1,points.size()):
		view._queue_brush(points[i-1],points[i])
		var count := maxi(absi(points[i].x-points[i-1].x),absi(points[i].y-points[i-1].y))
		for n in range(count+1):
			var cell := Vector2i(Vector2(points[i-1]).lerp(Vector2(points[i]),float(n)/count).round())
			for item in empty.cells_in_brush(cell,2): expected[item] = true
	check(view.pending_tools.size() < points.size()-1,"only collinear consecutive segments coalesce")
	while view.has_pending_edits(): view.flush_tools(1000)
	var written := 0
	for chunk in empty.chunks.values(): written += chunk.tiles.count(WorldState.Terrain.GRASS)
	check(written == expected.size(),"coalescing preserves exact coverage including corners and negative coordinates")
	for cell in expected: check(empty.walkable(cell),"every reference stroke cell survives coalescing")
	root.size = Vector2i(640,480); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frame()
	view.zoom = 2.0; view.go_to_cell(Vector2i.ZERO,false)
	view._process(0.016); await frame()
	var point := view.cell_to_local(Vector2i.ZERO)+Vector2(2,2)
	var image := root.get_texture().get_image()
	var color := image.get_pixelv(Vector2i(point))
	check(color.g > color.b and color.r > color.b,"applied stroke is visible before detailed baking completes")
	view.cancel_input(); view.tool = "water"; view.brush_radius = 2; view._queue_brush(Vector2i.ZERO,Vector2i.ZERO)
	while view.has_pending_edits(): view.flush_tools(1000)
	view._process(0.016); await frame()
	image = root.get_texture().get_image(); color = image.get_pixelv(Vector2i(point))
	check(color.b > color.r,"new water immediately replaces the previous land preview")
	var second := WorldState.new(); view.set_world(second)
	check(view.brush_previews.is_empty() and view.pending_tools.is_empty(),"switching worlds releases preview state and queued commands")
	view.queue_free(); await frame()
	print("Terrain update: %d failures" % failures)
	quit(1 if failures else 0)
