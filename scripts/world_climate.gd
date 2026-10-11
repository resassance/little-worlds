class_name WorldClimate
extends RefCounted

const NAMES := ["Умеренный", "Пустыня", "Тропики", "Тайга", "Тундра", "Снег"]
const COLORS := [Color("a2bd78"), Color("d3b279"), Color("619c70"), Color("74918a"), Color("a7ac99"), Color("dce5dd")]
const FOOD := [1.0, 0.25, 1.4, 0.8, 0.5, 0.25]

static func defaults() -> Dictionary:
	return {"mode": "uniform", "biome": 0, "equator": 64, "scale": 4096, "seasons": false, "forest_regrowth": true}

static func biome(world, cell: Vector2i) -> int:
	if world.biome_overrides.has(cell): return world.biome_overrides[cell]
	if world.climate.mode != "belts": return int(world.climate.biome)
	var latitude := absf(float(cell.y - int(world.climate.equator))) / int(world.climate.scale)
	var damp := posmod(hash(Vector3i(floori(cell.x / 32.0), floori(cell.y / 32.0), world.world_seed)), 100)
	if latitude < 0.22: return 2 if damp >= 35 else 1
	if latitude < 0.7: return 0
	if latitude < 1.0: return 3
	if latitude < 1.35: return 4
	return 5

static func season(world) -> int:
	return (world.ticks / (WorldLife.YEAR / 4)) % 4 if world.climate.seasons else 1

static func yield_factor(world, cell: Vector2i) -> float:
	var result: float = FOOD[biome(world, cell)]
	if world.climate.seasons:
		result *= [1.0, 1.15, 0.9, 0.45][season(world)]
	return result

static func growth_delta(world, cell: Vector2i, before: int, after: int) -> int:
	var factor: float = FOOD[biome(world, cell)]
	return floori(after * factor) - floori(before * factor)

static func hunger_factor(world, person: Dictionary) -> float:
	var cold: bool = biome(world, Vector2i(person.x, person.y)) >= 4 or (world.climate.seasons and season(world) == 3)
	if not cold: return 1.0
	var supplies: Dictionary = WorldCivilization.get_data(world, person.home)
	return 1.05 if not supplies.is_empty() and supplies.stock.cloth > 0 else 1.25

static func paint(world, center: Vector2i, radius: int, value: int) -> bool:
	if value < 0 or value >= NAMES.size() or radius < 0 or radius > 64: return false
	var points: Array[Vector2i] = world.cells_in_brush(center, radius)
	var additional := 0
	for cell in points:
		if world.walkable(cell) and not world.biome_overrides.has(cell): additional += 1
	if world.biome_overrides.size() + additional > 65536: return false
	for cell in points:
		if world.walkable(cell):
			world._grow(world.regions.get_region(world, WorldState.chunk_of(cell)))
			world.biome_overrides[cell] = value
	world.touch_terrain(center, radius)
	world.changed.emit()
	return true

static func configure(world, mode: String, value: int, equator: int, scale: int, seasons: bool) -> void:
	if mode not in ["uniform", "belts", "manual"] or value < 0 or value >= NAMES.size(): return
	for key in world.region_keys(): world._grow(world.regions.get_region(world, key))
	world.climate = {"mode": mode, "biome": value, "equator": clampi(equator, -999999, 999999), "scale": clampi(scale, 32, 1000000), "seasons": seasons, "forest_regrowth": bool(world.climate.forest_regrowth)}
	world.revision += 1
	for key in world.region_keys(): world.revisions[key] = world.revision
	world.terrain_changed.emit()
	world.changed.emit()

static func step(world) -> void:
	if world.climate.seasons and world.ticks%(WorldLife.YEAR/4)==0:
		world.revision+=1
		for key in world.region_keys(): world.revisions[key]=world.revision
		world.terrain_changed.emit()
	if world.ticks % WorldEconomy.DAY_TICKS != 0 or not world.climate.forest_regrowth: return
	for cell in world.stumps.keys():
		if world.ticks - int(world.stumps[cell]) < WorldLife.YEAR * 2: continue
		if world.terrain_at(cell) != WorldState.Terrain.GRASS:
			world.stumps.erase(cell)
			continue
		if biome(world, cell) in [1, 4, 5] or world.fires.has(cell) or not world.building_at(cell).is_empty(): continue
		var food: int = world.food_at(cell)
		world._set_terrain(cell, WorldState.Terrain.FOREST)
		world._set_food(cell, food)
		world.stumps.erase(cell)
		world.terrain_changed.emit()

static func describe(world, cell: Vector2i) -> String:
	return "Климат: %s%s" % [NAMES[biome(world, cell)], " · " + ["весна", "лето", "осень", "зима"][season(world)] if world.climate.seasons else ""]

static func save(world) -> Dictionary:
	var overrides: Array = []
	for cell in world.biome_overrides: overrides.append([cell.x, cell.y, world.biome_overrides[cell]])
	var stumps: Array = []
	for cell in world.stumps: stumps.append([cell.x, cell.y, world.stumps[cell]])
	return {"settings": world.climate.duplicate(), "overrides": overrides, "stumps": stumps}

static func restore(world, data: Variant) -> bool:
	if not data is Dictionary or not data.get("settings") is Dictionary: return false
	var value: Dictionary = data.settings
	if value.get("mode") not in ["uniform", "belts", "manual"] or not value.get("seasons") is bool or not value.get("forest_regrowth") is bool: return false
	for key in ["biome", "equator", "scale"]:
		if not WorldState._integer(value.get(key)): return false
	if value.biome < 0 or value.biome >= NAMES.size() or value.scale < 32 or value.scale > 1000000 or absi(value.equator) >= WorldState.COORD_LIMIT: return false
	world.climate = value.duplicate()
	for key in ["biome", "equator", "scale"]: world.climate[key] = int(world.climate[key])
	for name in ["overrides", "stumps"]:
		if not data.get(name) is Array or data[name].size() > (65536 if name == "overrides" else 4096): return false
		var target: Dictionary = world.biome_overrides if name == "overrides" else world.stumps
		for row in data[name]:
			if not row is Array or row.size() != 3: return false
			for item in row:
				if not WorldState._integer(item): return false
			var cell := Vector2i(row[0], row[1])
			if not world.inside(cell) or target.has(cell): return false
			if name == "overrides" and (row[2] < 0 or row[2] >= NAMES.size()): return false
			if name == "stumps" and (row[2] < 0 or row[2] > world.ticks): return false
			target[cell] = int(row[2])
	return true
