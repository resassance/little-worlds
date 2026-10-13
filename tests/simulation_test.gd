extends SceneTree

var failures: int = 0
var checks: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	var a := WorldState.new()
	var b := WorldState.new()
	a.generate(42817)
	b.generate(42817)
	check(a.tiles == b.tiles, "same seed produces same terrain")
	b.generate(71)
	check(a.tiles != b.tiles, "different seed changes terrain")
	check(a.tiles.size() == 128 * 128, "map dimensions")
	check(a.tiles.has(WorldState.Terrain.WATER) and a.tiles.has(WorldState.Terrain.FOREST), "island has sea and forests")
	check(not a.add_person(Vector2i(0, 0)), "people cannot spawn in water")
	check(not a.add_person(Vector2i(-1, 0)), "out-of-bounds spawn is rejected")
	a.populate_demo()
	check(a.people.size() == 6, "demo creates six settlers")
	for i in 100:
		a.step()
	check(not a.towns.is_empty(), "settlers establish a town")
	check(a.people.size() >= 6, "settlers survive the first days")
	check(a.towns[0].food > 0 and a.towns[0].wood > 0, "settlement gathers food and wood")
	var center := Vector2i(a.towns[0].x, a.towns[0].y)
	WorldWeather.set_rate(a, 0)
	a.paint(center, 3, WorldState.Terrain.FOREST)
	a.ignite(center, 2)
	check(not a.fires.is_empty(), "lightning starts fire")
	a.rain(center, 5)
	check(a.fires.is_empty(), "rain extinguishes nearby fire")
	check(a.food_at(center) == 8, "rain restores food")
	a.ignite(center, 1)
	a.wet_until = a.ticks + 40
	for i in 25:
		a.step()
	check(a.fires.is_empty(), "fire expires")
	check(a.terrain_at(center) == WorldState.Terrain.GRASS, "burnt forest becomes grass")
	WorldWeather.set_rate(a, 2)
	a.ignite(center, 1)
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	check(loaded != null, "JSON roundtrip accepts valid state")
	if loaded != null:
		check(JSON.stringify(a.to_dict()) == JSON.stringify(loaded.to_dict()), "JSON roundtrip preserves complete state")
		for i in 350:
			a.step()
			loaded.step()
		check(JSON.stringify(a.to_dict()) == JSON.stringify(loaded.to_dict()), "loaded simulation follows identical RNG trajectory")
	var test_path := "user://test-world.json"
	check(SaveStore.save_world(a, test_path) == OK, "save writes successfully")
	var disk := SaveStore.load_world(test_path)
	check(disk != null and JSON.stringify(disk.to_dict()) == JSON.stringify(a.to_dict()), "disk save reloads exactly")

	if a.people.is_empty(): a.add_person(a.nearest_land(center, 40), false)
	var invalid := a.to_dict()
	invalid.chunks[0].tiles[0] = 99
	check(WorldState.from_dict(invalid) == null, "invalid terrain rejected")
	invalid = a.to_dict()
	invalid.people[0].x = WorldState.COORD_LIMIT
	check(WorldState.from_dict(invalid) == null, "invalid entity coordinates rejected")
	invalid = a.to_dict()
	invalid.version = 999
	check(WorldState.from_dict(invalid) == null, "unsupported save version rejected")
	invalid = a.to_dict()
	invalid.people[0].hunger = "invalid"
	check(WorldState.from_dict(invalid) == null, "malformed entity fields rejected")
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(SaveStore.load_world(test_path) == null, "corrupt JSON rejected")
	DirAccess.remove_absolute(test_path)
	var huge := WorldState.new()
	huge.generate(42817)
	var initial_regions := huge.chunks.size()
	var far := Vector2i(-900000, 700000)
	check(huge.terrain_at(far) == WorldState.Terrain.WATER and huge.food_at(far) == 0, "missing regions are empty ocean")
	check(huge.chunks.size() == initial_regions, "reading distant ocean allocates nothing")
	check(huge.paint(far, 64, WorldState.Terrain.FOREST), "large brush creates distant continent")
	check(huge.chunks.size() < initial_regions + 30, "distance between islands consumes no regions")
	check(huge.walkable(far) and huge.nearest_land(far, 3) == far, "negative coordinates support walking and nearest-land lookup")
	check(WorldState.chunk_of(Vector2i(-1, -33)) == Vector2i(-1, -2), "negative chunk coordinates floor correctly")
	var boundary := Vector2i(-32, -32)
	huge.paint(boundary, 2, WorldState.Terrain.FOREST)
	huge.ignite(boundary, 2)
	check(huge.fires.has(boundary + Vector2i.LEFT) and huge.fires.has(boundary + Vector2i.RIGHT), "fire spans chunk borders")
	huge.rain(boundary, 3)
	check(huge.fires.is_empty(), "rain spans negative chunk borders")
	for delta in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.ONE]: huge.add_person(far + delta, false)
	huge.populate_demo()
	for i in 100: huge.step()
	check(huge.towns.size() >= 2, "distant communities both establish settlements")
	var huge_before := JSON.stringify(huge.to_dict())
	huge.food_at(far)
	check(JSON.stringify(huge.to_dict()) == huge_before, "resource inspection cannot change saved simulation state")
	huge._set_food(boundary, 0)
	var cycles := huge.regrowth
	for i in 40: huge.step()
	check(huge.food_at(boundary) == mini(8, huge.regrowth - cycles), "uninhabited distant resources regrow without being visited")
	check(SaveStore.save_world(huge, test_path) == OK, "regional save writes distant continents")
	var manifest_file := FileAccess.open(test_path, FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	check(manifest.has("regions") and not manifest.has("chunks"), "save manifest references independent region files")
	var huge_loaded := SaveStore.load_world(test_path)
	check(huge_loaded != null and JSON.stringify(huge_loaded.to_dict()) == JSON.stringify(huge.to_dict()), "regional disk roundtrip preserves distant communities and RNG")
	if huge_loaded != null:
		for i in 200:
			huge.step()
			huge_loaded.step()
		check(JSON.stringify(huge_loaded.to_dict()) == JSON.stringify(huge.to_dict()), "remote simulations continue identically after loading")
	var region_path: String = (test_path + ".regions").path_join(manifest.regions[0].file)
	var region_file := FileAccess.open(region_path, FileAccess.READ)
	var original_region := region_file.get_as_text()
	region_file.close()
	region_file = FileAccess.open(region_path, FileAccess.WRITE)
	region_file.store_string(original_region.replace('"tiles":', '"bad_tiles":'))
	region_file.close()
	check(SaveStore.load_world(test_path) == null, "tampered region fails hash verification")
	region_file = FileAccess.open(region_path, FileAccess.WRITE)
	region_file.store_string(original_region)
	region_file.close()
	check(SaveStore.load_world(test_path) != null, "repairing region restores intact snapshot")

	var saved_state := JSON.stringify(SaveStore.load_world(test_path).to_dict())
	huge.paint(Vector2i(500000, -500000), 1, WorldState.Terrain.GRASS)
	var blocked_name := ""
	for region in huge.to_dict().chunks:
		if region.x == WorldState.chunk_of(Vector2i(500000, -500000)).x:
			blocked_name = JSON.stringify(region).sha256_text() + ".json.tmp"
			break
	var blocked_path: String = (test_path + ".regions").path_join(blocked_name)
	DirAccess.make_dir_absolute(blocked_path)
	check(SaveStore.save_world(huge, test_path) != OK, "failed region write is reported")
	check(JSON.stringify(SaveStore.load_world(test_path).to_dict()) == saved_state, "failed save preserves previous complete snapshot")
	DirAccess.remove_absolute(blocked_path)
	var legacy := {"version": 1, "width": 128, "height": 128, "seed": a.world_seed, "ticks": a.ticks, "next_id": a.next_id,
		"tiles": Array(a.tiles), "food": Array(a.food), "people": a.people.duplicate(true), "towns": a.towns.duplicate(true), "fires": {},
		"history": a.history.duplicate(true), "rng_state": str(a.rng.state), "wet_until": a.wet_until, "drought_until": a.drought_until}

	for person in legacy.people:
		for field in ["name", "rations", "cargo", "cargo_kind", "energy", "job", "task", "birth_tick", "sex", "parents", "ancestors", "generation", "guardian", "partner", "household", "courting", "bond", "birth_due", "last_birth", "care_until", "health", "skills", "traits", "links", "social_need", "lesson", "trained_by", "ideas", "vocation"]: person.erase(field)
	for cell in a.fires: legacy.fires[a.index_of(cell)] = a.fires[cell]
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(legacy))) != null, "original 128x128 saves migrate to chunks")
	check(SaveStore._write_atomic(test_path, JSON.stringify(legacy)) == OK and SaveStore.load_world(test_path) != null, "legacy disk saves load through migration")
	var migrated := SaveStore.load_world(test_path)
	var preserved_people: bool = migrated.people.size() == legacy.people.size()
	for i in legacy.people.size():
		for field in legacy.people[i]:
			if migrated.people[i][field] != legacy.people[i][field]: preserved_people = false
	check(migrated.tiles == a.tiles and migrated.food == a.food and preserved_people, "migration preserves terrain, resources and inhabitants")
	var reclaim := WorldState.new()
	reclaim.paint(Vector2i(-1, -1), 4, WorldState.Terrain.FOREST)
	reclaim.paint(Vector2i(-1, -1), 4, WorldState.Terrain.WATER)
	check(reclaim.chunks.is_empty(), "erasing all land reclaims empty ocean regions")

	var bounded := WorldState.new()
	for x in WorldState.MAX_CHUNKS: bounded._set_terrain(Vector2i(x * WorldState.CHUNK_SIZE, 0), WorldState.Terrain.GRASS)
	var before_budget := JSON.stringify(bounded.to_dict())
	check(not bounded.paint(Vector2i(0, 50000), 3, WorldState.Terrain.GRASS), "region budget rejects excessive allocation")
	check(JSON.stringify(bounded.to_dict()) == before_budget, "rejected brush leaves world unchanged")
	check(not huge.paint(Vector2i(WorldState.COORD_LIMIT, 0), 2, WorldState.Terrain.GRASS), "coordinate limit rejects invalid terrain edits")
	var duplicate := huge.to_dict()
	duplicate.chunks.append(duplicate.chunks[0])
	check(WorldState.from_dict(duplicate) == null, "duplicate chunks rejected")
	duplicate = huge.to_dict()
	duplicate.chunks[0].epoch = huge.regrowth + 1
	check(WorldState.from_dict(duplicate) == null, "future resource epochs rejected")
	var relocated := WorldState.new()
	relocated.generate(42817)
	relocated.populate_demo()
	var old_pos := Vector2i(relocated.people[0].x, relocated.people[0].y)
	relocated.paint(old_pos, 1, WorldState.Terrain.WATER)
	for p in relocated.people:
		check(relocated.walkable(Vector2i(p.x, p.y)), "painting water leaves people on valid ground")
	var stress := WorldState.new()
	stress.generate(42817)
	var land: Array[Vector2i] = []
	for y in stress.height:
		for x in stress.width:
			if stress.walkable(Vector2i(x, y)):
				land.append(Vector2i(x, y))
	for i in WorldState.MAX_PEOPLE:
		stress.add_person(land[(i * 13) % land.size()], false)
	check(not stress.add_person(land[0]), "population cap enforced")
	var start := Time.get_ticks_usec()
	for i in 600:
		stress.step()
	var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0
	for p in stress.people:
		if not stress.walkable(Vector2i(p.x, p.y)):
			check(false, "stress population stays on valid cells")
	check(stress.history.size() <= 60, "chronicle remains bounded")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(stress.to_dict()))) != null, "long simulation remains serializable")
	print("Stress: %d initial people, 600 steps, %.1f ms total, %.2f ms/step (headless desktop CPU)." % [WorldState.MAX_PEOPLE, elapsed_ms, elapsed_ms / 600.0])
	print("Simulation: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
