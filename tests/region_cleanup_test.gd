extends SceneTree

var failures := 0

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error("FAIL: "+label)

func create_cache() -> WorldState:
	var world := WorldState.new()
	for i in WorldRegions.CACHE_LIMIT+24: world._set_terrain(Vector2i(i*WorldState.CHUNK_SIZE,0),WorldState.Terrain.GRASS)
	world.regions.trim(world)
	return world

func _initialize() -> void:
	WorldRegions.deferred_cleanup = true
	var active := create_cache()
	var active_path := active.regions.directory
	var retired := create_cache()
	var retired_path := retired.regions.directory
	retired = null
	check(DirAccess.dir_exists_absolute(retired_path),"retiring a world only queues its cache directory")
	var slices := 0
	while not WorldRegions.retired_directories.is_empty() or WorldRegions.cleanup_folder != null:
		WorldRegions.cleanup_retired(1); slices += 1
	check(slices > 20 and not DirAccess.dir_exists_absolute(retired_path),"old cache files are removed incrementally")
	check(DirAccess.dir_exists_absolute(active_path),"cleanup never removes an active world's cache")
	var cell: Vector2i = active.regions.cold.keys()[0]*WorldState.CHUNK_SIZE
	check(active.terrain_at(cell) == WorldState.Terrain.GRASS,"active cold data remains readable after cleanup")
	active.regions.clear()
	check(active.regions.directory.is_empty() and DirAccess.dir_exists_absolute(active_path),"clearing cache data also defers file removal")
	WorldRegions.cleanup_retired(0)
	check(not DirAccess.dir_exists_absolute(active_path),"deferred cleanup eventually finishes")
	print("Region cleanup: %d failures" % failures)
	quit(1 if failures else 0)
