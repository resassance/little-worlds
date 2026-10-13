class_name WorldWeather
extends RefCounted

const MODULUS := 2147483647
const KINDS := ["rain", "thunder", "drought", "frost", "storm"]
const TITLES := {"rain": "Затяжной дождь", "thunder": "Сухая гроза", "drought": "Местная засуха", "frost": "Заморозки", "storm": "Морской шторм"}
const MESSAGES := {"rain": "Дождь гасит огонь и понемногу восстанавливает съедобные растения.", "thunder": "Молнии могут поджечь сухую траву и лес.", "drought": "Растения теряют запасы, рост полей замедляется.", "frost": "Посевы растут медленнее, жителям нужна тёплая одежда.", "storm": "Мореплаватели пережидают непогоду, расходуя еду; суда могут пострадать."}

static func defaults(seed_value: int, tick: int = 0) -> Dictionary:
	return {"rate": 2, "rng": 1 + posmod(hash("%d:weather" % seed_value), MODULUS - 1), "next_tick": tick + 80, "sequence": 0, "active": []}

static func draw(world) -> float:
	world.weather.rng = (int(world.weather.rng) * 48271) % MODULUS
	return float(world.weather.rng) / MODULUS

static func index(world, count: int) -> int:
	return mini(count - 1, int(draw(world) * count))

static func contains(event: Dictionary, cell: Vector2i) -> bool:
	return cell.distance_squared_to(Vector2i(event.x, event.y)) <= int(event.radius) * int(event.radius)

static func at(world, cell: Vector2i, kind: String) -> bool:
	for event in world.weather.active:
		if event.kind == kind and int(event.until) > world.ticks and contains(event, cell): return true
	return false

static func wet(world, cell: Vector2i) -> bool:
	return at(world, cell, "rain") or at(world, cell, "storm")

static func farm_work(world, cell: Vector2i) -> bool:
	if at(world, cell, "drought"): return posmod(world.ticks + cell.x + cell.y, 4) == 0
	if at(world, cell, "frost"): return posmod(world.ticks + cell.x + cell.y, 3) == 0
	return true

static func set_rate(world, rate: int) -> void:
	world.weather.rate = clampi(rate, 0, 3)
	if rate == 0:
		world.weather.active.clear()
		world.log_event("Тихая природа", "Случайные природные события отключены.")
	world.weather.next_tick = maxi(world.ticks + 40, int(world.weather.next_tick))

static func schedule(world) -> void:
	var rate: int = world.weather.rate
	world.weather.next_tick = world.ticks + [160, 120, 60, 40][rate] + int(draw(world) * [100, 100, 80, 60][rate])
	if rate == 0 or world.weather.active.size() >= 3: return
	var center := WorldState.NO_CELL
	var aboard := false
	if not world.voyages.is_empty() and draw(world) < 0.35:
		var ship: Dictionary = world.voyages[index(world, world.voyages.size())]
		if ship.phase in ["outbound", "returning"]:
			center = WorldMaritime.position(ship); aboard = true
	if center == WorldState.NO_CELL and not world.towns.is_empty():
		var home: Dictionary = world.towns[index(world, world.towns.size())]
		center = Vector2i(home.x, home.y)
	elif center == WorldState.NO_CELL and not world.people.is_empty():
		var member: Dictionary = world.people[index(world, world.people.size())]
		center = Vector2i(member.x, member.y)
	elif center == WorldState.NO_CELL and not world.chunks.is_empty():
		var keys: Array = world.chunks.keys()
		for attempt in 8:
			var key: Vector2i = keys[index(world, keys.size())]
			var candidate := key * WorldState.CHUNK_SIZE + Vector2i(index(world, 32), index(world, 32))
			if world.terrain_at(candidate) in [WorldState.Terrain.GRASS, WorldState.Terrain.FOREST]: center = candidate; break
	if center == WorldState.NO_CELL: return
	var biome := WorldClimate.biome(world, center)
	var cold: bool = biome >= 3 or (world.climate.seasons and WorldClimate.season(world) == 3)
	var coast := aboard
	if not coast:
		for direction in WorldState.DIRECTIONS:
			if world.terrain_at(center + direction * 7) == WorldState.Terrain.WATER: coast = true; break
	var weights := [4.0 if biome == 2 else 2.0, 0.0 if cold else (1.0 if rate == 1 else 2.0), 0.0 if cold else (3.0 if biome == 1 else 1.0), 2.0 if cold else 0.0, 2.0 if coast and rate > 1 else 0.0]
	if aboard: weights = [1.0, 0.0, 0.0, 0.0, 5.0]
	var total := 0.0
	for weight in weights: total += weight
	var roll := draw(world) * total
	var kind := "rain"
	for i in weights.size():
		roll -= weights[i]
		if roll < 0: kind = KINDS[i]; break
	start(world, kind, center, 8 + index(world, 5), 16 + index(world, 25))

static func start(world, kind: String, center: Vector2i, radius: int, duration: int) -> Dictionary:
	if not kind in KINDS or world.weather.active.size() >= 3 or not world.inside(center): return {}
	for existing in world.weather.active:
		if Vector2i(existing.x, existing.y).distance_squared_to(center) < (int(existing.radius) + radius) * (int(existing.radius) + radius): return {}
	world.weather.sequence += 1
	var event := {"id": int(world.weather.sequence), "kind": kind, "x": center.x, "y": center.y, "radius": clampi(radius, 1, 12), "started": world.ticks, "until": world.ticks + clampi(duration, 1, 60), "pulse": world.ticks, "strike_tick": -1, "strike_x": center.x, "strike_y": center.y}
	world.weather.active.append(event)
	world.log_event(TITLES[kind], "%s Область: %d, %d. Длительность: %d мес." % [MESSAGES[kind], center.x, center.y, ceili(float(event.until - world.ticks) / WorldEconomy.DAY_TICKS)])
	return event

static func describe(world, cell: Vector2i) -> String:
	for event in world.weather.active:
		if int(event.until) > world.ticks and contains(event, cell): return "\nПогода: " + TITLES[event.kind]
	return ""

static func restore(world, data: Variant) -> bool:
	if data == null: world.weather = defaults(world.world_seed, world.ticks); return true
	if not data is Dictionary or not data.get("active") is Array or data.active.size() > 3: return false
	for field in ["rate", "rng", "next_tick", "sequence"]:
		if not WorldState._integer(data.get(field)): return false
	if data.rate < 0 or data.rate > 3 or data.rng < 1 or data.rng >= MODULUS or data.next_tick < 0 or data.sequence < 0: return false
	var ids := {}
	var restored := defaults(world.world_seed, world.ticks)
	for field in ["rate", "rng", "next_tick", "sequence"]: restored[field] = int(data[field])
	for item in data.active:
		if not item is Dictionary or item.get("kind") not in KINDS: return false
		for field in ["id", "x", "y", "radius", "started", "until", "pulse", "strike_tick", "strike_x", "strike_y"]:
			if not WorldState._integer(item.get(field)): return false
		if item.id <= 0 or item.id > data.sequence or ids.has(int(item.id)) or item.radius < 1 or item.radius > 12: return false
		if item.started < 0 or item.started > world.ticks or item.until <= item.started or item.until - item.started > 60 or item.pulse < item.started or item.pulse > world.ticks + 8: return false
		if item.strike_tick < -1 or item.strike_tick > world.ticks or not world.inside(Vector2i(item.x, item.y)) or not world.inside(Vector2i(item.strike_x, item.strike_y)): return false
		var event: Dictionary = item.duplicate()
		for field in ["id", "x", "y", "radius", "started", "until", "pulse", "strike_tick", "strike_x", "strike_y"]: event[field] = int(event[field])
		ids[int(item.id)] = true; restored.active.append(event)
	world.weather = restored
	return true
