extends SceneTree

var failures := 0

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error("FAIL: "+label)

func age(world: WorldState) -> void:
	var job := WorldLandscapeJob.new(world)
	while not job.finished: job.unit()

func _initialize() -> void:
	var world := WorldState.new()
	world.paint(Vector2i.ZERO,40,WorldState.Terrain.GRASS)
	world.add_person(Vector2i(-1,0),false)
	var member: Dictionary = world.people[0]
	var rng_state := world.rng.state
	var metrics := world.metrics.duplicate(true)
	for i in 64:
		var previous := Vector2i(member.x,member.y)
		member.x = 0 if member.x == -1 else -1
		world.ticks = (i/2)*2+1
		world.track_person_move(member,previous)
	check(world.landscape.paths.size() == 2,"actual adjacent movement creates only visited trail cells")
	check(WorldLandscape.stage(WorldLandscape.wear_at(world.landscape.paths[Vector2i.ZERO],world.ticks)) == 3,"repeated traffic widens a trail")
	check(world.landscape.paths[Vector2i.ZERO].links == 1 and world.landscape.paths[Vector2i(-1,0)].links == 2,"trail connects across the negative chunk boundary")
	check(world.rng.state == rng_state and world.metrics == metrics,"trails do not alter RNG or resource accounting")
	var line := WorldState.new(); line.paint(Vector2i.ZERO,20,WorldState.Terrain.GRASS)
	var walker := {"id":1,"x":-12,"y":0}
	for x in range(-11,13):
		var before := Vector2i(walker.x,0); walker.x = x; line.ticks += 1; line.landscape.moved(line,walker,before)
	for x in range(-11,12): check(line.landscape.paths[Vector2i(x,0)].links == 3,"every straight-route cell retains both links")
	var count := world.landscape.paths.size()
	var previous := Vector2i(member.x,member.y); member.x = 20
	world.track_person_move(member,previous)
	check(world.landscape.paths.size() == count,"teleports and sea travel do not paint trails across the map")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	var loaded := WorldState.from_dict(saved)
	check(loaded != null and JSON.stringify(loaded.landscape.save()) == JSON.stringify(world.landscape.save()),"trail wear and directions survive save and load")
	var legacy: Dictionary = saved.duplicate(true); legacy.version = 10; legacy.erase("landscape")
	check(WorldState.from_dict(legacy) != null,"version 10 worlds load without landscape history")
	var large := WorldState.from_dict(saved.duplicate(true))
	for i in 300: large._set_terrain(Vector2i(100000+i*32,0),WorldState.Terrain.GRASS)
	large.regions.trim(large)
	var restored_large := WorldState.from_dict(JSON.parse_string(JSON.stringify(large.to_dict())))
	check(restored_large != null and restored_large.landscape.save() == large.landscape.save(),"historical paths in cold regions survive loading a large world")
	for mutation in ["wear","future","links","duplicate","water","missing"]:
		var broken: Dictionary = saved.duplicate(true)
		match mutation:
			"wear": broken.landscape.paths[0][2] = 17
			"future": broken.landscape.paths[0][3] = world.ticks+1
			"links": broken.landscape.paths[0][4] = 16
			"duplicate": broken.landscape.paths.append(broken.landscape.paths[0].duplicate())
			"water": broken.landscape.paths[0][0] = 100000
			"missing": broken.erase("landscape")
		check(WorldState.from_dict(broken) == null,"malformed trail history rejected: "+mutation)
	world.ticks = 400; age(world)
	check(world.landscape.paths.is_empty() and world.landscape.path_regions.is_empty(),"unused trails regrow and release spatial records")
	world.paint(Vector2i(4,0),0,WorldState.Terrain.FOREST)
	world.harvest_wood(Vector2i(4,0),12)
	check(world.stumps.has(Vector2i(4,0)) and world.landscape.site_regions[Vector2i.ZERO][Vector2i(4,0)] == "stump","real logging creates an indexed stump")
	world.ticks += WorldLife.YEAR*2
	WorldClimate.regrow(world,Vector2i(4,0))
	check(not world.landscape.site_regions.get(Vector2i.ZERO,{}).has(Vector2i(4,0)),"forest recovery removes the stump image")
	world.landscape.scar(world,Vector2i(31,0),"ruin",3)
	check(world.landscape.scar_regions.has(Vector2i(1,0)),"large ruins are indexed across chunk boundaries")
	world.landscape.clear_cell(Vector2i(32,1))
	check(world.landscape.scars.is_empty(),"painting any part of a ruin removes its remaining footprint")
	world.landscape.scar(world,Vector2i(31,0),"ruin",3)
	world.ticks += WorldLife.YEAR*4; age(world)
	check(world.landscape.scars.is_empty() and world.landscape.scar_regions.is_empty(),"old ruins regrow and release every indexed chunk")
	check(WorldAudit.conserved(world),"visible history preserves finite-resource balances")
	print("Landscape: ",failures," failures")
	quit(1 if failures else 0)
