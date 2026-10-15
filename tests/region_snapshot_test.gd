extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func fixture() -> WorldState:
	var world := WorldState.new()
	world.generate(42817)
	world.populate_demo()
	for i in 150: world._set_terrain(Vector2i(100000 + i * 32, 0), WorldState.Terrain.GRASS)
	world.regions.trim(world)
	return world

func target(world: WorldState) -> Vector2i:
	for key in world.regions.cold:
		if key.x > 1000: return key
	return WorldState.NO_CELL

func run() -> void:
	var world := fixture()
	var key := target(world)
	var before := world.regions.cold.duplicate(true)
	var reads := world.regions.cold_reads
	var first := world.regions.capture(world, key)
	var second := world.regions.capture(world, key)
	var old_path: String = before[key].path
	check(world.regions.cold_reads == reads, "capturing cold terrain performs no file read")
	check(world.regions.cold == before, "snapshot leaves residency and cold metadata unchanged")
	check(world.regions.snapshot_files[old_path] == 2, "overlapping snapshots retain independent file references")
	world._set_terrain(key * 32, WorldState.Terrain.FOREST)
	world.regions.access[key] = -1
	world.regions.trim(world, WorldState.NO_CELL, 1)
	check(world.regions.cold.has(key), "modified region is evicted again")
	check(world.regions.cold[key].path != old_path, "changed terrain writes a new immutable file version")
	check(FileAccess.file_exists(old_path), "old version remains while a snapshot needs it")
	check(world.regions.decode_snapshot(key, first).tiles[0] == WorldState.Terrain.GRASS, "snapshot reads original ground after eviction and repainting")
	check(world.terrain_at(key * 32) == WorldState.Terrain.FOREST, "live world reads its new ground")
	first = {}
	check(world.regions.snapshot_files[old_path] == 1 and FileAccess.file_exists(old_path), "releasing one snapshot keeps the other readable")
	var old_directory := world.regions.directory
	world.generate(482)
	WorldRegions.cleanup_retired(0)
	check(DirAccess.dir_exists_absolute(old_directory), "regenerating world does not remove a retained cache directory")
	check(world.regions.decode_snapshot(key, second).tiles[0] == WorldState.Terrain.GRASS, "snapshot remains readable after world regeneration")
	second = {}
	WorldRegions.cleanup_retired(0)
	check(not DirAccess.dir_exists_absolute(old_directory), "last snapshot release reclaims the retired directory")
	check(world.regions.snapshot_files.is_empty() and world.regions.snapshot_directories.is_empty(), "snapshot leases do not accumulate")
	world = fixture()
	key = target(world)
	first = world.regions.capture(world, key)
	old_path = world.regions.cold[key].path
	world.regions.get_region(world, key)
	world.regions.access[key] = -1
	world.regions.trim(world, WorldState.NO_CELL, 1)
	check(world.regions.cold[key].path == old_path, "unchanged eviction may reuse the same content file")
	first = {}
	check(FileAccess.file_exists(old_path) and world.terrain_at(key * 32) == WorldState.Terrain.GRASS, "releasing a reused snapshot cannot delete a live cold file")
	var cache_files := DirAccess.open(world.regions.directory).get_files()
	check(cache_files.size() <= world.regions.cold.size(), "unreferenced old file versions are reclaimed")
	var path := "user://region-snapshot-failure.json"
	var saved := JSON.stringify(world.to_dict())
	var complete := WorldSaveJob.new(world, path)
	complete.advance(0)
	check(complete.result == OK, "initial complete save succeeds")
	var pending := WorldSaveJob.new(world, path)
	reads = world.regions.cold_reads
	while not pending.snapshot_ready and not pending.finished: pending.advance(1)
	check(world.regions.cold_reads == reads, "save releases simulation before reading any cold files")
	check(not world.regions.snapshot_files.is_empty(), "pending save owns deferred terrain versions")
	key = target(world)
	var corrupt := FileAccess.open(world.regions.cold[key].path, FileAccess.WRITE)
	corrupt.store_string("invalid cache payload")
	corrupt.close()
	pending.advance(0)
	check(pending.finished and pending.result == ERR_FILE_CORRUPT, "corrupted deferred data fails the save")
	check(world.regions.snapshot_files.is_empty(), "failed save releases all captured file versions")
	var loaded := SaveStore.load_world(path)
	check(loaded != null and JSON.stringify(loaded.to_dict()) == saved, "failed deferred save preserves previous committed world")
	var rich := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))
	var rich_before := JSON.stringify(rich.to_dict())
	var rich_save := WorldSaveJob.new(rich, "user://rich-metadata-snapshot.json")
	while not rich_save.snapshot_ready and not rich_save.finished: rich_save.advance(1)
	check(rich_save.header.is_empty() and not rich_save.header_snapshot.is_empty(), "metadata serialization is deferred until simulation is released")
	rich.step()
	rich.towns[0].food = 0
	rich.societies[0].practice.food += 1
	rich.civilization[rich.towns[0].id].stock.stone += 1
	rich.households[0].food += 1
	rich.climate.seasons = not rich.climate.seasons
	rich.history[0].message = "live history changed after capture"
	WorldWeather.start(rich, "rain", Vector2i(rich.towns[0].x, rich.towns[0].y), 3, 20)
	if not rich.voyages.is_empty(): rich.voyages[0].food = maxi(0, int(rich.voyages[0].food) - 1)
	rich_save.advance(0)
	var rich_loaded := SaveStore.load_world("user://rich-metadata-snapshot.json")
	check(rich_save.result == OK and rich_loaded != null and JSON.stringify(rich_loaded.to_dict()) == rich_before, "deferred metadata is isolated from changes to households, technologies, stocks, weather, history and voyages")
	print("Region snapshot: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
