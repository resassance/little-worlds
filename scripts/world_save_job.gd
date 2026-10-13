class_name WorldSaveJob
extends RefCounted

var world: WorldState
var path: String
var directory: String
var keys: Array[Vector2i] = []
var cursor := 0
var phase := 0
var references: Array[Dictionary] = []
var used: Dictionary = {}
var obsolete: PackedStringArray = []
var file: FileAccess
var result: Error = OK
var finished := false
var captured_regions: Array[Dictionary] = []
var captured_people: Array[Dictionary] = []
var region_contents: Array[Dictionary] = []
var people_contents := PackedStringArray()
var header := ""
var header_job: WorldSaveHeaderJob
var snapshot_ready: bool:
	get: return phase >= 3 and not finished

func _init(value: WorldState, destination: String = SaveStore.SAVE_PATH) -> void:
	world = value; path = destination; directory = path+".regions"
	if world.stepping or world.regions.failed:
		_fail(ERR_BUSY if world.stepping else ERR_FILE_CORRUPT); return
	result = DirAccess.make_dir_recursive_absolute(directory)
	if result != OK: _fail(result); return
	keys.assign(world.region_keys())

func _fail(error: Error) -> void:
	result = error; finished = true
	if file != null: file.close(); file = null

func advance(budget_usec: int = 2500) -> bool:
	if budget_usec > 0 and OS.has_feature("web") and phase in [5,6,8] and bool(JavaScriptBridge.eval("typeof GodotFS !== 'undefined' && GodotFS._syncing")): return false
	var deadline := Time.get_ticks_usec()+budget_usec
	while not finished:
		var previous := phase
		_unit()
		if OS.has_feature("web") and (phase == 7 or previous == 7): break
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func finish() -> void:
	if OS.has_feature("web"):
		while not finished and phase < 7: _unit()
		finished = true
	else: advance(0)

func _unit() -> void:
	if phase <= 4: _prepare_unit()
	elif OS.has_feature("web"): _unit_web()
	else: _unit_disk()

func _next(next_phase: int) -> void:
	phase = next_phase; cursor = 0

func _prepare_unit() -> void:
	match phase:
		0:
			if cursor >= keys.size(): _next(1); return
			var key := keys[cursor]
			var packet := world.regions.capture(world,key)
			if packet.is_empty() or world.regions.failed: _fail(ERR_FILE_CORRUPT); return
			captured_regions.append({"key":key,"packet":packet}); cursor += 1
		1:
			if header_job == null:
				header_job = WorldSaveHeaderJob.new(world,[])
				header_job.data.erase("regions")
			if not header_job.finished: header_job.unit(); return
			header = header_job.result; header_job = null; _next(2)
		2:
			if cursor >= world.people.size(): _next(3); return
			captured_people.append(world.people[cursor].duplicate(true)); cursor += 1
		3:
			if cursor >= captured_regions.size(): captured_regions.clear(); _next(4); return
			var captured := captured_regions[cursor]
			var key: Vector2i = captured.key
			var chunk := world.regions.decode_snapshot(key,captured.packet)
			if chunk.is_empty(): _fail(ERR_FILE_CORRUPT); return
			var content := JSON.stringify({"x":key.x,"y":key.y,"tiles":Array(chunk.tiles),"food":Array(chunk.food),"wood":Array(chunk.wood),"epoch":chunk.epoch})
			var digest := content.sha256_text()
			var name_value := digest+".json"
			region_contents.append({"content":content,"file":name_value,"digest":digest})
			references.append({"x":key.x,"y":key.y,"file":name_value}); used[name_value] = true
			captured_regions[cursor] = {}; cursor += 1
		4:
			if cursor >= captured_people.size(): captured_people.clear(); _next(5); return
			people_contents.append(JSON.stringify(captured_people[cursor],"",true,true))
			captured_people[cursor] = {}; cursor += 1

func _header_prefix() -> String:
	return header.left(header.length()-1)+',"regions":'+JSON.stringify(references)+',"people":['

func _unit_disk() -> void:
	match phase:
		5:
			if cursor >= region_contents.size(): _next(6); return
			var region := region_contents[cursor]
			var target := directory.path_join(region.file)
			if not FileAccess.file_exists(target) or FileAccess.get_sha256(target) != region.digest:
				var error := SaveStore._write_atomic(target,region.content)
				if error != OK: _fail(error); return
			region.erase("content"); cursor += 1
		6:
			file = FileAccess.open(path+".tmp",FileAccess.WRITE)
			if file == null: _fail(FileAccess.get_open_error()); return
			file.store_string(_header_prefix())
			header = ""; region_contents.clear(); _next(7)
		7:
			if cursor >= people_contents.size(): _next(8); return
			if cursor > 0: file.store_string(",")
			file.store_string(people_contents[cursor]); cursor += 1
		8:
			file.store_string("]}"); file.flush()
			var error := file.get_error()
			file.close(); file = null
			if error != OK: _fail(error); return
			error = DirAccess.rename_absolute(path+".tmp",path)
			if error != OK: _fail(error); return
			people_contents.clear(); _next(9)
		9:
			_collect_obsolete(); _next(10)
		10: _cleanup_unit()

func _unit_web() -> void:
	match phase:
		5:
			if cursor >= region_contents.size(): _next(6); return
			for i in 4:
				if cursor >= region_contents.size(): break
				var region := region_contents[cursor]
				var target := directory.path_join(region.file)
				if not FileAccess.file_exists(target) or FileAccess.get_sha256(target) != region.digest:
					var error := _write_web_region(target,region.content)
					if error != OK: _fail(error); return
				region.erase("content"); cursor += 1
		6:
			JavaScriptBridge.eval("GodotFS._lw_commit_status=0; GodotFS._lw_commit_checking=false")
			var content := _header_prefix()+",".join(people_contents)+"]}"
			var error := SaveStore._write_atomic(path,content)
			if error != OK: _fail(error); return
			region_contents.clear(); people_contents.clear(); header = ""; _next(7)
		7:
			var status := _web_commit_status()
			if status < 0: _fail(ERR_CANT_CREATE); return
			if status == 0: return
			_collect_obsolete(); _next(8)
		8: _cleanup_unit()

func _collect_obsolete() -> void:
	var folder := DirAccess.open(directory)
	if folder != null: obsolete = folder.get_files()

func _cleanup_unit() -> void:
	if cursor >= obsolete.size(): finished = true; return
	var name_value := obsolete[cursor]; cursor += 1
	if SaveStore._region_name(name_value) and not used.has(name_value): DirAccess.remove_absolute(directory.path_join(name_value))

func _write_web_region(target: String, content: String) -> Error:
	var temporary := ProjectSettings.globalize_path(target+".tmp")
	var destination := ProjectSettings.globalize_path(target)
	var script := "try {FS.writeFile(%s,%s,{encoding:'utf8'}); FS.rename(%s,%s); true;} catch (_) {false;}" % [JSON.stringify(temporary),JSON.stringify(content),JSON.stringify(temporary),JSON.stringify(destination)]
	return OK if bool(JavaScriptBridge.eval(script)) else ERR_CANT_CREATE

func _web_commit_status() -> int:
	return int(JavaScriptBridge.eval("""
if (!GodotFS._lw_commit_checking) {
 GodotFS._lw_commit_checking=true;
 GodotOS._fs_sync_promise.then(error=>{GodotFS._lw_commit_status=error?-1:1;});
}
GodotFS._lw_commit_status || 0
"""))
