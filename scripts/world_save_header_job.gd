class_name WorldSaveHeaderJob
extends RefCounted

var world
var data: Dictionary
var maps: Array[Dictionary] = []
var map_cursor := 0
var row_cursor := 0
var phase := 0
var stack: Array[Dictionary] = []
var parts := PackedStringArray()
var result := ""
var finished := false
var capturing := false
var copies: Array[Dictionary] = []
var copy_cursor := 0

func _init(value, references: Array[Dictionary], capture_only: bool = false, snapshot: Dictionary = {}) -> void:
	world = value
	capturing = capture_only
	if not snapshot.is_empty():
		data = snapshot
		return
	data = {"version": WorldState.SAVE_VERSION, "chunk_size": WorldState.CHUNK_SIZE, "seed": world.world_seed,
		"climate": {"settings": world.climate, "overrides": [], "stumps": []},
		"civilization": {"towns": world.civilization.values(), "metrics": world.industry, "deposits": []},
		"maritime": {"voyages": world.voyages, "contacts": world.contacts, "explored": world.explored_coasts, "fishing": []},
		"journeys": world.journeys, "ticks": world.ticks, "next_id": world.next_id, "regions": references, "regrowth": world.regrowth,
		"towns": world.towns, "buildings": world.buildings, "metrics": world.metrics, "fires": [],
		"societies": world.societies, "households": world.households, "ancestry_archive": world.ancestry_archive,
		"history": world.history, "rng_state": str(world.rng.state), "wet_until": world.wet_until, "drought_until": world.drought_until, "weather": world.weather,"landscape":{"paths":[],"scars":[]}}
	maps = [
		{"source": world.biome_overrides, "keys": world.biome_overrides.keys(), "target": data.climate.overrides, "kind": 0},
		{"source": world.stumps, "keys": world.stumps.keys(), "target": data.climate.stumps, "kind": 0},
		{"source": world.mineral_deposits, "keys": world.mineral_deposits.keys(), "target": data.civilization.deposits, "kind": 0},
		{"source": world.fishing, "keys": world.fishing.keys(), "target": data.maritime.fishing, "kind": 1},
		{"source": world.fires, "keys": world.fires.keys(), "target": data.fires, "kind": 2},
		{"source":world.landscape.paths,"keys":world.landscape.paths.keys(),"target":data.landscape.paths,"kind":3},
		{"source":world.landscape.scars,"keys":world.landscape.scars.keys(),"target":data.landscape.scars,"kind":4}]
	if capturing:
		data.climate.settings = world.climate.duplicate(true)
		data.civilization.metrics = world.industry.duplicate(true)
		data.metrics = world.metrics.duplicate()
		data.weather = world.weather.duplicate(true)
		for key in ["towns", "buildings", "societies", "households", "ancestry_archive", "history", "journeys"]: _copy_array(data, key)
		_copy_array(data.civilization, "towns")
		_copy_array(data.maritime, "voyages")
		_copy_array(data.maritime, "contacts")
		var explored: Dictionary = data.maritime.explored
		data.maritime.explored = {}
		copies.append({"source": explored, "keys": explored.keys(), "target": data.maritime.explored, "cursor": 0, "dictionary": true})

func _copy_array(container: Dictionary, key: String) -> void:
	var source: Array = container[key]
	container[key] = []
	copies.append({"source": source, "target": container[key], "cursor": 0, "dictionary": false})

func _copy_unit() -> void:
	if copy_cursor >= copies.size():
		copies.clear(); maps.clear()
		finished = true
		return
	var item: Dictionary = copies[copy_cursor]
	if item.cursor >= item.source.size(): copy_cursor += 1; return
	var key: Variant = item.keys[item.cursor] if item.dictionary else item.cursor
	var value: Variant = item.source[key]
	if value is Dictionary or value is Array: value = value.duplicate(true)
	if item.dictionary: item.target[key] = value
	else: item.target.append(value)
	item.cursor += 1


func unit() -> void:
	if finished: return
	if phase == 2: _copy_unit(); return
	if phase == 0:
		if map_cursor >= maps.size():
			if capturing: phase = 2; return
			stack.append({"value": data, "cursor": -1, "depth": 0}); phase = 1
			return
		var mapping: Dictionary = maps[map_cursor]
		if row_cursor >= mapping.keys.size(): map_cursor += 1; row_cursor = 0; return
		var cell: Vector2i = mapping.keys[row_cursor]; row_cursor += 1
		match mapping.kind:
			0: mapping.target.append([cell.x, cell.y, mapping.source[cell]])
			1: mapping.target.append([cell.x, cell.y, mapping.source[cell].day, mapping.source[cell].amount])
			2: mapping.target.append({"x": cell.x, "y": cell.y, "ttl": mapping.source[cell]})
			3:
				var item: Dictionary = mapping.source[cell]
				mapping.target.append([cell.x,cell.y,item.wear,item.tick,item.links])
			4:
				var item: Dictionary = mapping.source[cell]
				mapping.target.append([cell.x,cell.y,item.kind,item.size,item.tick])
		return
	if stack.is_empty():
		result = "".join(parts)
		parts.clear(); data.clear(); maps.clear()
		finished = true
		return
	var frame: Dictionary = stack.back()
	var value: Variant = frame.value
	var dictionary: bool = value is Dictionary
	if frame.cursor == -1:
		if not (value is Array or dictionary) or (frame.depth > 1 and dictionary and value.size() <= 64):
			parts.append(JSON.stringify(value, "", true, true)); stack.pop_back(); return
		parts.append("{" if dictionary else "[")
		if dictionary: frame.keys = value.keys()
		frame.cursor = 0
		return
	if frame.cursor >= value.size():
		parts.append("}" if dictionary else "]"); stack.pop_back(); return
	if frame.cursor > 0: parts.append(",")
	var child: Variant
	if dictionary:
		var key: Variant = frame.keys[frame.cursor]
		parts.append(JSON.stringify(str(key)) + ":")
		child = value[key]
	else: child = value[frame.cursor]
	frame.cursor += 1
	stack.append({"value": child, "cursor": -1, "depth": frame.depth + 1})
