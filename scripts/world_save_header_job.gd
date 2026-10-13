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

func _init(value, references: Array[Dictionary]) -> void:
	world = value
	data = {"version": WorldState.SAVE_VERSION, "chunk_size": WorldState.CHUNK_SIZE, "seed": world.world_seed,
		"climate": {"settings": world.climate, "overrides": [], "stumps": []},
		"civilization": {"towns": world.civilization.values(), "metrics": world.industry, "deposits": []},
		"maritime": {"voyages": world.voyages, "contacts": world.contacts, "explored": world.explored_coasts, "fishing": []},
		"journeys": world.journeys, "ticks": world.ticks, "next_id": world.next_id, "regions": references, "regrowth": world.regrowth,
		"towns": world.towns, "buildings": world.buildings, "metrics": world.metrics, "fires": [],
		"societies": world.societies, "households": world.households, "ancestry_archive": world.ancestry_archive,
		"history": world.history, "rng_state": str(world.rng.state), "wet_until": world.wet_until, "drought_until": world.drought_until, "weather": world.weather}
	maps = [
		{"source": world.biome_overrides, "keys": world.biome_overrides.keys(), "target": data.climate.overrides, "kind": 0},
		{"source": world.stumps, "keys": world.stumps.keys(), "target": data.climate.stumps, "kind": 0},
		{"source": world.mineral_deposits, "keys": world.mineral_deposits.keys(), "target": data.civilization.deposits, "kind": 0},
		{"source": world.fishing, "keys": world.fishing.keys(), "target": data.maritime.fishing, "kind": 1},
		{"source": world.fires, "keys": world.fires.keys(), "target": data.fires, "kind": 2}]

func unit() -> void:
	if finished: return
	if phase == 0:
		if map_cursor >= maps.size():
			stack.append({"value": data, "cursor": -1, "depth": 0}); phase = 1
			return
		var mapping: Dictionary = maps[map_cursor]
		if row_cursor >= mapping.keys.size(): map_cursor += 1; row_cursor = 0; return
		var cell: Vector2i = mapping.keys[row_cursor]; row_cursor += 1
		match mapping.kind:
			0: mapping.target.append([cell.x, cell.y, mapping.source[cell]])
			1: mapping.target.append([cell.x, cell.y, mapping.source[cell].day, mapping.source[cell].amount])
			2: mapping.target.append({"x": cell.x, "y": cell.y, "ttl": mapping.source[cell]})
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
