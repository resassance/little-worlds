class_name WorldRegions
extends RefCounted

const CACHE_LIMIT := 128
var cold: Dictionary = {}
var clock := 0
var access: Dictionary = {}
var directory := ""
var failed := false

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
	if world.chunks.size() > CACHE_LIMIT * 2: trim(world, key)
	return chunk

func trim(world, pinned: Vector2i = WorldState.NO_CELL) -> void:
	if world.chunks.size() <= CACHE_LIMIT: return
	if directory.is_empty():
		directory = "user://region-cache/%d-%d" % [Time.get_ticks_usec(), get_instance_id()]
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			failed = true
			return
	var required := {pinned: true}
	for member in world.people: required[WorldState.chunk_of(Vector2i(member.x, member.y))] = true
	for home in world.towns: required[WorldState.chunk_of(Vector2i(home.x, home.y))] = true
	for cell in world.fires: required[WorldState.chunk_of(cell)] = true
	var keys: Array = world.chunks.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i): return access.get(a, 0) < access.get(b, 0))
	for key in keys:
		if world.chunks.size() <= CACHE_LIMIT: break
		if required.has(key): continue
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
	if not directory.is_empty():
		var folder := DirAccess.open(directory)
		if folder != null:
			for name in folder.get_files(): folder.remove(name)
		DirAccess.remove_absolute(directory)
	directory = ""
	failed = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not directory.is_empty():
		var folder := DirAccess.open(directory)
		if folder != null:
			for name in folder.get_files(): folder.remove(name)
		DirAccess.remove_absolute(directory)
