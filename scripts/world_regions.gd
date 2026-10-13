class_name WorldRegions
extends RefCounted

const CACHE_LIMIT := 128
var cold: Dictionary = {}
var clock := 0
var access: Dictionary = {}
var directory := ""
var failed := false
var pins: Dictionary = {}
var job_pins: Dictionary = {}
var pin_signature: Array = []
static var retired_directories: Array[String] = []
static var cleanup_folder: DirAccess
static var cleanup_path := ""
static var deferred_cleanup := false

static func retire(directory_path: String) -> void:
	retired_directories.append(directory_path)
	if not deferred_cleanup: cleanup_retired(0)

static func cleanup_retired(budget_usec: int = 200) -> void:
	var deadline := Time.get_ticks_usec()+budget_usec
	while not retired_directories.is_empty() or cleanup_folder != null:
		if cleanup_folder == null:
			cleanup_path = retired_directories.pop_back()
			cleanup_folder = DirAccess.open(cleanup_path)
			if cleanup_folder != null: cleanup_folder.list_dir_begin()
		else:
			var entry := cleanup_folder.get_next()
			if entry.is_empty():
				cleanup_folder.list_dir_end(); cleanup_folder = null
				DirAccess.remove_absolute(cleanup_path)
			elif not cleanup_folder.current_is_dir(): cleanup_folder.remove(entry)
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: return

static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func get_region(world, key: Vector2i) -> Dictionary:
	clock += 1
	access[key] = clock
	if world.chunks.has(key): return world.chunks[key]
	if not cold.has(key): return {}
	var metadata: Dictionary = cold[key]
	var file := FileAccess.open(metadata.path, FileAccess.READ)
	if file == null:
		failed = true
		return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if digest(bytes) != metadata.hash:
		failed = true
		return {}
	var chunk: Variant = bytes_to_var(bytes.decompress_dynamic(65536, FileAccess.COMPRESSION_GZIP))
	if not chunk is Dictionary or chunk.get("coord") != key or not WorldState._integer(chunk.get("epoch")):
		failed = true
		return {}
	for field in ["tiles", "food", "wood"]:
		if not chunk.get(field) is PackedInt32Array or chunk[field].size() != WorldState.CHUNK_SIZE * WorldState.CHUNK_SIZE:
			failed = true
			return {}
	world.chunks[key] = chunk
	cold.erase(key)
	if world.chunks.size() > CACHE_LIMIT * 2: trim(world, key, 1)
	return chunk

func trim(world, pinned: Vector2i = WorldState.NO_CELL, max_regions: int = 0) -> void:
	if world.chunks.size() <= CACHE_LIMIT: return
	if directory.is_empty():
		directory = "user://region-cache/%d-%d" % [Time.get_ticks_usec(), get_instance_id()]
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			failed = true
			return
	var signature := [world.ticks, world.people.size(), world.towns.size(), world.fires.size()]
	if signature != pin_signature:
		pin_signature = signature
		pins.clear()
		for member in world.people: pins[WorldState.chunk_of(Vector2i(member.x, member.y))] = true
		for home in world.towns: pins[WorldState.chunk_of(Vector2i(home.x, home.y))] = true
		for cell in world.fires: pins[WorldState.chunk_of(cell)] = true
	if world.chunks.size() <= maxi(CACHE_LIMIT, pins.size()): return
	var trimmed := 0
	var keys: Array = world.chunks.keys()
	if max_regions > 0:
		var selected: Array = []
		for i in max_regions:
			var oldest := WorldState.NO_CELL
			var oldest_access := 9223372036854775807
			for candidate in keys:
				if pins.has(candidate) or job_pins.has(candidate) or candidate == pinned or selected.has(candidate): continue
				var visited: int = int(access.get(candidate, 0))
				if visited < oldest_access: oldest = candidate; oldest_access = visited
			if oldest == WorldState.NO_CELL: break
			selected.append(oldest)
		keys = selected
	else:
		keys.sort_custom(func(a: Vector2i, b: Vector2i): return access.get(a, 0) < access.get(b, 0))
	for key in keys:
		if world.chunks.size() <= CACHE_LIMIT: break
		if pins.has(key) or job_pins.has(key) or key == pinned: continue
		if max_regions > 0 and trimmed >= max_regions: break
		trimmed += 1
		var chunk: Dictionary = world.chunks[key]
		var path := directory.path_join("%d_%d.bin" % [key.x, key.y])
		var bytes := var_to_bytes(chunk).compress(FileAccess.COMPRESSION_GZIP)
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			failed = true
			break
		file.store_buffer(bytes)
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
			failed = true
			break
		if world.bounds_dirty.has(key):
			var low := Vector2i(WorldState.CHUNK_SIZE, WorldState.CHUNK_SIZE)
			var high := Vector2i(-1, -1)
			for i in chunk.tiles.size():
				if chunk.tiles[i] == WorldState.Terrain.WATER: continue
				var point := Vector2i(i % WorldState.CHUNK_SIZE, i / WorldState.CHUNK_SIZE)
				low.x = mini(low.x, point.x); low.y = mini(low.y, point.y)
				high.x = maxi(high.x, point.x); high.y = maxi(high.y, point.y)
			if high.x >= 0: world.region_bounds[key] = Rect2i(key * WorldState.CHUNK_SIZE + low, high - low + Vector2i.ONE)
			else: world.region_bounds.erase(key)
			world.bounds_dirty.erase(key)
		cold[key] = {"path": path, "hash": digest(bytes)}
		world.chunks.erase(key)

func clear() -> void:
	cold.clear()
	access.clear()
	pins.clear(); job_pins.clear(); pin_signature.clear()
	if not directory.is_empty(): retire(directory)
	directory = ""
	failed = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not directory.is_empty(): retire(directory)
