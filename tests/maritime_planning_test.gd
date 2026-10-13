extends SceneTree

var failures := 0

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error("FAIL: "+label)

func fixture() -> WorldState:
	return WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))

func _initialize() -> void:
	var world := fixture()
	var home: Dictionary = world.towns[0]
	home.sea_search_cursor = 777
	home.sea_route_cursor = 7
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(loaded != null and loaded.towns[0].sea_search_cursor == 777,"discovery cursor survives save and load")
	check(loaded != null and loaded.towns[0].sea_route_cursor == 7,"route retry cursor survives save and load")
	for cursor in [-1,0.5,WorldState.MAX_CHUNKS]:
		home.sea_search_cursor = cursor
		check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) == null,"invalid discovery cursor rejected")
	home.erase("sea_search_cursor")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null,"older worlds without a discovery cursor still load")
	var vessel: Dictionary = {}
	for building in world.buildings:
		if building.kind in ["boat","sailboat"]:
			vessel = building
			home = WorldEconomy.town(world,vessel.town)
			break
	for member in world.people: member.hunger = 50
	var destination := {"land":Vector2i(100000,0),"water":Vector2i(99999,0)}
	check(not WorldMaritime.launch(world,home,vessel,destination),"hungry crew does not depart")
	check(world.sea_routes.is_empty(),"unavailable crew never triggers route planning")
	for member in world.people:
		member.home = home.id; member.hunger = 0; member.energy = 100; member.health = 100; member.birth_due = -1; member.task = {}
	world.population_dirty = true
	check(not WorldMaritime.crew_candidates(world,home,1).is_empty(),"ready crew exists for the supply test")
	destination = {"land":Vector2i(900000,0),"water":Vector2i(899999,0)}
	check(not WorldMaritime.launch(world,home,vessel,destination),"voyage beyond hold capacity cannot depart")
	check(world.sea_routes.is_empty(),"impossible supplies never trigger route planning")
	var sea := WorldState.new()
	sea.paint(Vector2i.ZERO,4,WorldState.Terrain.GRASS)
	for i in 1000: sea._set_terrain(Vector2i(100000+i*32,0),WorldState.Terrain.GRASS)
	var a := Vector2i(-40,0)
	var b := Vector2i(40,0)
	check(not WorldMaritime.segment_clear(sea,a,b),"land still blocks a direct segment among distant regions")
	var route := WorldMaritime.route(sea,a,b)
	check(route.size() > 2,"local obstacle can be bypassed despite a thousand distant regions")
	for i in range(1,route.size()):
		check(WorldMaritime.segment_clear(sea,Vector2i(route[i-1][0],route[i-1][1]),Vector2i(route[i][0],route[i][1])),"every detour segment stays in water")
	check(WorldMaritime.segment_clear(sea,Vector2i(-40,-40),Vector2i(900000,-40)),"long empty ocean remains passable")
	for origin in [Vector2i(-16,-16),Vector2i(16,16),Vector2i(100016,16),Vector2i(100040,-8),Vector2i(60000,0)]:
		var nearest := WorldNearestLandJob.new(sea,origin,16)
		while not nearest.finished: nearest.unit()
		check(nearest.result == sea.nearest_land(origin,16),"batched land search preserves the nearest cell and empty result")
	print("Maritime planning: ",failures," failures")
	quit(1 if failures else 0)
