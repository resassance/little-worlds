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
var web_regions: Array[Dictionary] = []
var web_people := PackedStringArray()
var web_header := ""

func _init(value: WorldState, destination: String = SaveStore.SAVE_PATH) -> void:
	world = value
	path = destination
	directory = path + ".regions"
	if world.stepping or world.regions.failed:
		_fail(ERR_BUSY if world.stepping else ERR_FILE_CORRUPT)
		return
	result = DirAccess.make_dir_recursive_absolute(directory)
	if result != OK: _fail(result); return
	keys.assign(world.region_keys())

func _fail(error: Error) -> void:
	result = error
	finished = true
	if file != null: file.close(); file = null

func advance(budget_usec: int = 2500) -> bool:
	if budget_usec > 0 and OS.has_feature("web") and phase in [3,4,6] and bool(JavaScriptBridge.eval("typeof GodotFS !== 'undefined' && GodotFS._syncing")): return false
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		var before_phase := phase
		_unit()
		if OS.has_feature("web") and (phase == 5 or before_phase == 5): break
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func finish() -> void:
	if OS.has_feature("web"):
		while not finished and phase < 5: _unit_web()
		finished = true
	else: advance(0)

func _unit() -> void:
	if OS.has_feature("web"):
		_unit_web()
		return
	match phase:
		0:
			if cursor >= keys.size(): phase = 1; cursor = 0; return
			var key := keys[cursor]
			var chunk: Dictionary = world.regions.get_region(world, key)
			if chunk.is_empty() or world.regions.failed: _fail(ERR_FILE_CORRUPT); return
			var content := JSON.stringify({"x":key.x,"y":key.y,"tiles":Array(chunk.tiles),"food":Array(chunk.food),"wood":Array(chunk.wood),"epoch":chunk.epoch})
			var digest := content.sha256_text()
			var name_value := digest + ".json"
			var target := directory.path_join(name_value)
			if not FileAccess.file_exists(target) or FileAccess.get_sha256(target) != digest:
				var error := SaveStore._write_atomic(target, content)
				if error != OK: _fail(error); return
			references.append({"x":key.x,"y":key.y,"file":name_value})
			used[name_value] = true
			cursor += 1
		1:
			var data := world.to_dict(false, false)
			data.erase("chunks"); data.erase("people")
			data.regions = references
			file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
			if file == null: _fail(FileAccess.get_open_error()); return
			var header := JSON.stringify(data)
			file.store_string(header.left(header.length() - 1) + ',"people":[')
			phase = 2
		2:
			if cursor < world.people.size():
				if cursor > 0: file.store_string(",")
				file.store_string(JSON.stringify(world.people[cursor]))
				cursor += 1
			else:
				file.store_string("]}")
				file.flush()
				var error := file.get_error()
				file.close(); file = null
				if error != OK: _fail(error); return
				error = DirAccess.rename_absolute(path + ".tmp", path)
				if error != OK: _fail(error); return
				phase = 3
		3:
			var folder := DirAccess.open(directory)
			if folder != null: obsolete = folder.get_files()
			cursor = 0; phase = 4
		4:
			if cursor < obsolete.size():
				var name_value := obsolete[cursor]
				if SaveStore._region_name(name_value) and not used.has(name_value): DirAccess.remove_absolute(directory.path_join(name_value))
				cursor += 1
			else: finished = true

func _unit_web() -> void:
	match phase:
		0:
			if cursor >= keys.size(): phase = 1; cursor = 0; return
			var key := keys[cursor]
			var chunk: Dictionary = world.regions.get_region(world,key)
			if chunk.is_empty() or world.regions.failed: _fail(ERR_FILE_CORRUPT); return
			var content := JSON.stringify({"x":key.x,"y":key.y,"tiles":Array(chunk.tiles),"food":Array(chunk.food),"wood":Array(chunk.wood),"epoch":chunk.epoch})
			var digest := content.sha256_text()
			var name_value := digest + ".json"
			web_regions.append({"content":content,"file":name_value,"digest":digest})
			references.append({"x":key.x,"y":key.y,"file":name_value})
			used[name_value] = true
			cursor += 1
		1:
			var data := world.to_dict(false,false)
			data.erase("chunks"); data.erase("people")
			data.regions = references
			web_header = JSON.stringify(data)
			phase = 2
		2:
			if cursor < world.people.size():
				web_people.append(JSON.stringify(world.people[cursor])); cursor += 1
			else: cursor = 0; phase = 3
		3:
			if cursor >= web_regions.size(): phase = 4; return
			for i in 4:
				if cursor >= web_regions.size(): break
				var region := web_regions[cursor]
				var target := directory.path_join(region.file)
				if not FileAccess.file_exists(target) or FileAccess.get_sha256(target) != region.digest:
					var error := _write_web_region(target,region.content)
					if error != OK: _fail(error); return
				cursor += 1
		4:
			JavaScriptBridge.eval("GodotFS._lw_commit_status=0; GodotFS._lw_commit_checking=false")
			var content := web_header.left(web_header.length()-1) + ',"people":[' + ",".join(web_people) + "]}"
			var error := SaveStore._write_atomic(path,content)
			if error != OK: _fail(error); return
			web_regions.clear(); web_people.clear(); web_header = ""
			phase = 5
		5:
			var status := _web_commit_status()
			if status < 0: _fail(ERR_CANT_CREATE); return
			if status == 0: return
			var folder := DirAccess.open(directory)
			if folder != null: obsolete = folder.get_files()
			cursor = 0; phase = 6

		6:
			if cursor < obsolete.size():
				var name_value := obsolete[cursor]
				if SaveStore._region_name(name_value) and not used.has(name_value): DirAccess.remove_absolute(directory.path_join(name_value))
				cursor += 1
			else: finished = true

func _write_web_region(target: String, content: String) -> Error:
	var temporary := ProjectSettings.globalize_path(target + ".tmp")
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
