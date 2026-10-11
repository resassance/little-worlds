class_name WorldClimateConfigureJob
extends RefCounted

var world
var settings: Dictionary
var keys: Array = []
var cursor := 0
var tile_cursor := 0
var chunk: Dictionary = {}
var key := Vector2i.ZERO
var phase := 0
var amount := 0
var ordinary := false
var colors_changed := false
var finished := false

func _init(value, mode: String, biome: int, equator: int, scale: int, seasons: bool) -> void:
	world = value
	if mode not in ["uniform", "belts", "manual"] or biome < 0 or biome >= WorldClimate.NAMES.size(): finished = true; return
	settings = {"mode": mode, "biome": biome, "equator": clampi(equator, -999999, 999999), "scale": clampi(scale, 32, 1000000), "seasons": seasons, "forest_regrowth": bool(world.climate.forest_regrowth)}
	for field in ["mode", "biome", "equator", "scale"]:
		if settings[field] != world.climate[field]: colors_changed = true
	if colors_changed: keys = world.region_keys()
	ordinary = world.climate.mode == "uniform" and world.climate.biome == 0 and world.biome_overrides.is_empty()

func advance(budget_usec: int = 2000) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func unit() -> void:
	if finished: return
	match phase:
		0:
			if cursor >= keys.size(): phase = 1; return
			if chunk.is_empty():
				key = keys[cursor]
				world.regions.job_pins[key] = true
				chunk = world.regions.get_region(world, key)
				if chunk.is_empty(): world.regions.job_pins.erase(key); cursor += 1; return
				amount = world.regrowth - int(chunk.epoch)
				if amount <= 0: world.regions.job_pins.erase(key); cursor += 1; chunk = {}; return
				return
			for i in range(tile_cursor, mini(tile_cursor + WorldState.CHUNK_SIZE, chunk.food.size())):
				var cell := key * WorldState.CHUNK_SIZE + Vector2i(i % WorldState.CHUNK_SIZE, i / WorldState.CHUNK_SIZE)
				chunk.food[i] = mini(chunk.food[i] + (amount if ordinary else WorldClimate.growth_delta(world, cell, int(chunk.epoch), world.regrowth)), world.capacity(chunk.tiles[i]))
			tile_cursor += WorldState.CHUNK_SIZE
			if tile_cursor >= chunk.food.size():
				chunk.epoch = world.regrowth
				world.regions.job_pins.erase(key)
				tile_cursor = 0; cursor += 1; chunk = {}
		1:
			world.climate = settings
			if colors_changed: world.revision += 1
			world.workforce.plans.clear(); world.workforce.contributions.clear()
			WorldSociety.invalidate(world)
			phase = 2; cursor = 0
		2:
			if cursor < keys.size(): world.revisions[keys[cursor]] = world.revision; cursor += 1
			else:
				if colors_changed: world.terrain_changed.emit()
				world.changed.emit()
				finished = true
