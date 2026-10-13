class_name SaveStore
extends RefCounted

const SAVE_PATH := "user://world.json"
const MAX_SAVE_BYTES := 8 * 1024 * 1024
const MAX_REGION_BYTES := 64 * 1024

static func _write_atomic(path: String, content: String) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(temporary, path)

static func _region_name(name_value: String) -> bool:
	if name_value.length() != 69 or not name_value.ends_with(".json"): return false
	for character in name_value.left(64):
		if character not in "0123456789abcdef": return false
	return true

static func save_world(world: WorldState, path: String = SAVE_PATH) -> Error:
	if world.regions.failed: return ERR_FILE_CORRUPT


	var directory := path + ".regions"
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return error
	var data := world.to_dict(false)
	if data.is_empty(): return ERR_FILE_CORRUPT
	var regions: Array[Dictionary] = []
	var used := {}
	for key in world.region_keys():
		var chunk: Dictionary = world.regions.snapshot(world, key)
		if chunk.is_empty() or world.regions.failed: return ERR_FILE_CORRUPT
		var region := {"x": key.x, "y": key.y, "tiles": Array(chunk.tiles), "food": Array(chunk.food), "wood": Array(chunk.wood), "epoch": chunk.epoch}
		var content := JSON.stringify(region)
		var digest := content.sha256_text()
		var name_value := digest + ".json"
		var target := directory.path_join(name_value)
		if not FileAccess.file_exists(target) or FileAccess.get_sha256(target) != digest:
			error = _write_atomic(target, content)
			if error != OK: return error
		regions.append({"x": region.x, "y": region.y, "file": name_value})
		used[name_value] = true
	data.erase("chunks")
	data.regions = regions
	error = _write_atomic(path, JSON.stringify(data, "", true, true))
	if error != OK: return error

	var folder := DirAccess.open(directory)
	if folder != null:
		for name_value in folder.get_files():
			if _region_name(name_value) and not used.has(name_value): folder.remove(name_value)
	return OK

static func _read_json(path: String, limit: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > limit: return {}
	var json := JSON.new()
	var result := json.parse(file.get_as_text())
	file.close()
	return json.data if result == OK and json.data is Dictionary else {}

static func load_world(path: String = SAVE_PATH) -> WorldState:
	var data := _read_json(path, MAX_SAVE_BYTES)
	if data.is_empty(): return null

	if data.get("version") == 1 or data.has("chunks"): return WorldState.from_dict(data)
	if not data.get("regions") is Array or data.regions.size() > WorldState.MAX_CHUNKS: return null
	data.chunks = []
	var region_files := {}
	for reference in data.regions:
		if not reference is Dictionary or not reference.get("file") is String or not _region_name(reference.file): return null
		var target: String = (path + ".regions").path_join(reference.file)
		var file := FileAccess.open(target, FileAccess.READ)
		if file == null or file.get_length() > MAX_REGION_BYTES: return null
		file.close()
		if not WorldState._integer(reference.get("x")) or not WorldState._integer(reference.get("y")): return null
		var key := Vector2i(reference.x, reference.y)
		if region_files.has(key): return null
		region_files[key] = {"path": target, "hash": reference.file.left(64)}
		data.chunks.append({"x": key.x, "y": key.y})
	data.erase("regions")
	return WorldState.from_dict(data, region_files)
