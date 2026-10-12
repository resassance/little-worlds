extends SceneTree

var failures := 0
var maximum := 0
var slices := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: "+description)

func drain(view: WorldView) -> void:
	while view.has_pending_edits():
		var start := Time.get_ticks_usec()
		view.flush_tools(1000)
		maximum = maxi(maximum,Time.get_ticks_usec()-start); slices += 1

func stroke(view: WorldView, from: Vector2i, to: Vector2i, mode: String, radius: int) -> void:
	view.cancel_input(); view.tool = mode; view.brush_radius = radius
	view._paint_segment(from,to)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var view := WorldView.new()
	root.add_child(view); view.set_process(false)
	var world := WorldState.new()
	view.set_world(world)
	stroke(view,Vector2i(-40,-20),Vector2i(160,-20),"grass",2)
	check(world.region_count() == 0 and view.pending_tools.size() == 1,"input only queues a complete long stroke without editing or per-cell allocations")
	drain(view)
	for x in range(-40,161): check(world.walkable(Vector2i(x,-20)),"long stroke preserves every centre beyond the former 128-cell limit")
	var expected := {}
	for x in range(-40,161):
		for cell in world.cells_in_brush(Vector2i(x,-20),2): expected[cell] = true
	check(view.brush_cells_written == expected.size(),"overlapping stamps modify each covered cell once")
	view._paint_segment(Vector2i(160,-20),Vector2i(-40,-20)); drain(view)
	check(view.brush_cells_written == expected.size(),"reversing one stroke reuses coverage without repainting")
	stroke(view,Vector2i(-10,-20),Vector2i(20,-20),"water",3); drain(view)
	for x in range(-10,21): check(world.terrain_at(Vector2i(x,-20)) == WorldState.Terrain.WATER,"eraser covers the entire drag")
	stroke(view,Vector2i.ZERO,Vector2i(4,4),"forest",64); drain(view)
	check(world.wood_at(Vector2i.ZERO) == 12 and world.terrain_at(Vector2i(4,4)) == WorldState.Terrain.FOREST,"large forest brush finishes with resources intact")
	stroke(view,Vector2i(-3,-3),Vector2i(5,5),"biome_2",8); drain(view)
	check(WorldClimate.biome(world,Vector2i.ZERO) == 2,"biome stroke changes land climate")
	stroke(view,Vector2i(-3,-3),Vector2i(5,5),"fire",8); drain(view)
	check(world.fires.has(Vector2i.ZERO),"fire brush ignites every touched grass or forest cell")
	stroke(view,Vector2i(-3,-3),Vector2i(5,5),"rain",8); drain(view)
	check(not world.fires.has(Vector2i.ZERO) and world.food_at(Vector2i.ZERO) == 8 and world.wet_until > world.ticks,"rain brush extinguishes fire and restores resources")
	var inhabited := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))
	view.set_world(inhabited)
	var home: Dictionary = inhabited.towns[0]
	var center := Vector2i(home.x,home.y)
	stroke(view,center-Vector2i(8,0),center+Vector2i(8,0),"mountain",8); drain(view)
	for person in inhabited.people:
		if not WorldTravel.away(inhabited,person.id): check(inhabited.walkable(Vector2i(person.x,person.y)),"terrain replacement relocates remaining residents onto safe land")
	for town in inhabited.towns: check(inhabited.walkable(Vector2i(town.x,town.y)),"terrain replacement removes settlements without land")
	check(WorldAudit.conserved(inhabited),"terrain replacement conserves materials after lost homes and buildings")
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(inhabited.to_dict(),"",true,true)))
	check(loaded != null,"a completed inhabited brush edit saves and restores")
	var erase := WorldState.new(); view.set_world(erase)
	stroke(view,Vector2i.ZERO,Vector2i.ZERO,"grass",0); drain(view)
	stroke(view,Vector2i.ZERO,Vector2i.ZERO,"water",0); drain(view)
	check(erase.region_count() == 0 and erase.region_bounds.is_empty(),"erasing the last tile removes the empty region and its overview bounds")
	stroke(view,Vector2i(WorldState.COORD_LIMIT+8,0),Vector2i(WorldState.COORD_LIMIT+8,50),"grass",0)
	check(not view.has_pending_edits(),"a stroke completely outside world limits never starts a huge empty job")
	stroke(view,Vector2i(WorldState.COORD_LIMIT-4,0),Vector2i(WorldState.COORD_LIMIT+4,0),"grass",0); drain(view)
	for x in range(WorldState.COORD_LIMIT-4,WorldState.COORD_LIMIT): check(erase.walkable(Vector2i(x,0)),"a clipped stroke reaches the final legal cell")
	check(maximum < 16000,"brush processing never runs a whole stamp or whole navigation search in one slice")
	view.queue_free(); await process_frame
	print("Brush: slices %d, maximum %.2f ms, failures %d" % [slices,maximum/1000.0,failures])
	quit(1 if failures else 0)
