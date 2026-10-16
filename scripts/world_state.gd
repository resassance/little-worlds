class_name WorldState
extends RefCounted


signal terrain_changed
signal changed

enum Terrain { WATER, SAND, GRASS, FOREST, MOUNTAIN }
const MAP_SIZE := 128
const MAX_PEOPLE := 2000
const SAVE_VERSION := 14
const MAX_BUILDINGS := 2048
const CHUNK_SIZE := 32
const MAX_CHUNKS := 2048
const COORD_LIMIT := 1000000
const NO_CELL := Vector2i(-2147483648, -2147483648)
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const TERRAIN_NAMES := ["Вода", "Песок", "Равнина", "Лес", "Горы"]

var width: int = MAP_SIZE
var height: int = MAP_SIZE
var world_seed: int = 42817
var ticks: int = 0
var next_id: int = 1
var chunks: Dictionary = {}
var revisions: Dictionary = {}
var region_bounds: Dictionary = {}
var region_key_cache: Array = []
var region_key_count := -1
var bounds_dirty: Dictionary = {}
var revision := 0
var regrowth := 0

var tiles: PackedInt32Array:
	get:
		var result := PackedInt32Array()
		for y in height:
			for x in width: result.append(terrain_at(Vector2i(x, y)))
		return result
var food: PackedInt32Array:
	get:
		var result := PackedInt32Array()
		for y in height:
			for x in width: result.append(food_at(Vector2i(x, y)))
		return result
var people: Array[Dictionary] = []
var person_removals: Array[WorldPersonRemovalJob] = []
var removal_ids: Dictionary = {}
var person_index: Dictionary = {}
var households: Array[Dictionary] = []
var household_index: Dictionary = {}
var ancestry_archive: Array[Dictionary] = []
var life_dirty := false
var towns: Array[Dictionary] = []
var societies: Array[Dictionary] = []
var society_index: Dictionary = {}
var society_cache: Dictionary = {}
var buildings: Array[Dictionary] = []
var navigation: Dictionary = {}
var navigation_cleanup: Array[WorldNavigationCleanupJob] = []
var site_cache: Dictionary = {}
var sea_routes: Dictionary = {}
var sea_revision := 0
var survey_regions: Dictionary = {}
var occupied: Dictionary = {}
var building_index: Dictionary = {}
var claims: Dictionary = {}
var population_index: Dictionary = {}
var population_member_order: Dictionary = {}
var population_dirty := true
var population := WorldPopulation.new()
var workforce := WorldWorkforce.new()
var metrics: Dictionary = {}
var fires: Dictionary = {}
var fire_regions: Dictionary = {}
var fire_revision := 0
const FOREST_FIRE_TICKS := 12
const GRASS_FIRE_TICKS := 8
const RAIN_TICKS := 20
var history: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var wet_until: int = 0
var drought_until: int = 0
var weather: Dictionary = WorldWeather.defaults(42817)
var climate: Dictionary = WorldClimate.defaults()
var biome_overrides: Dictionary = {}
var stumps: Dictionary = {}
var civilization: Dictionary = {}
var mineral_deposits: Dictionary = {}
var industry: Dictionary = {"produced": {}, "consumed": {}, "lost": {}}
var voyages: Array[Dictionary] = []
var voyage_index: Dictionary = {}
var voyage_people: Dictionary = {}
var voyage_route_versions: Dictionary = {}
var contacts: Array[Dictionary] = []
var explored_coasts: Dictionary = {}
var fishing: Dictionary = {}
var journeys: Array[Dictionary] = []
var journey_index: Dictionary = {}
var journey_people: Dictionary = {}
var travel_paths: Dictionary = {}
var travel_path_revision := -1
var path_revision := 0
var history_revision := 0
var regions := WorldRegions.new()
var stepping := false
var profiling := false
var timings: Dictionary = {}
var landscape := WorldLandscape.new()
var heritage := WorldHeritage.new()
var networks := WorldNetworks.new()
var bridge_repair_needed := false

func _init() -> void:
	for key in WorldEconomy.METRICS: metrics[key] = 0
	for category in industry:
		industry[category] = WorldCivilization.empty_stock()

func generate(seed_value: int) -> void:
	landscape = WorldLandscape.new()
	heritage = WorldHeritage.new()
	networks = WorldNetworks.new()
	bridge_repair_needed = false
	heritage.initialize(seed_value)
	population.clear()
	workforce.end()
	world_seed = seed_value
	rng.seed = seed_value
	ticks = 0
	next_id = 1
	people.clear()
	person_index.clear()
	households.clear()
	household_index.clear()
	ancestry_archive.clear()
	life_dirty = false
	towns.clear()
	societies.clear()
	society_index.clear()
	society_cache.clear()
	climate = WorldClimate.defaults()
	biome_overrides.clear()
	stumps.clear()
	civilization.clear()
	mineral_deposits.clear()
	journeys.clear()
	journey_index.clear()
	journey_people.clear()
	voyages.clear()
	voyage_index.clear()
	voyage_people.clear()
	contacts.clear()
	explored_coasts.clear()
	fishing.clear()
	for category in industry: industry[category] = WorldCivilization.empty_stock()
	buildings.clear()
	occupied.clear()
	building_index.clear()
	navigation.clear(); site_cache.clear(); sea_routes.clear()
	travel_paths.clear(); travel_path_revision = -1; path_revision = 0
	sea_revision = 0
	survey_regions.clear()
	claims.clear()
	population_index.clear(); population_member_order.clear()
	population_dirty = true
	for key in WorldEconomy.METRICS: metrics[key] = 0
	fires.clear(); fire_regions.clear(); fire_revision += 1
	history.clear()
	history_revision += 1
	wet_until = 0
	drought_until = 0
	weather = WorldWeather.defaults(world_seed)
	chunks.clear()
	regions.clear()
	revisions.clear()
	region_bounds.clear(); region_key_cache.clear(); region_key_count = -1
	bounds_dirty.clear()
	regrowth = 0
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = seed_value + 19
	forest_noise.frequency = 0.09
	for y in height:
		for x in width:
			var nx := (float(x) / (width - 1) - 0.5) * 2.0
			var ny := (float(y) / (height - 1) - 0.5) * 2.0
			var elevation := 0.64 - Vector2(nx, ny).length() + noise.get_noise_2d(x, y) * 0.65
			var terrain := Terrain.WATER
			if elevation > 0.02:
				terrain = Terrain.SAND
			if elevation > 0.08:
				terrain = Terrain.GRASS
			if elevation > 0.13 and forest_noise.get_noise_2d(x, y) > -0.08:
				terrain = Terrain.FOREST
			if elevation > 0.49:
				terrain = Terrain.MOUNTAIN
			_set_terrain(Vector2i(x, y), terrain)
	log_event("Рождение мира", "Из воды появился новый остров. Seed: %d." % world_seed)
	terrain_changed.emit()
	changed.emit()

static func chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))

func region_keys() -> Array:
	var count := region_count()
	if region_key_count != count:
		region_key_cache = chunks.keys()
		for key in regions.cold: region_key_cache.append(key)
		region_key_cache.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
		region_key_count = count
	return region_key_cache.duplicate()

func region_count() -> int:
	return chunks.size() + regions.cold.size()

func has_region(key: Vector2i) -> bool:
	return chunks.has(key) or regions.cold.has(key)

static func local_index(cell: Vector2i) -> int:
	return posmod(cell.y, CHUNK_SIZE) * CHUNK_SIZE + posmod(cell.x, CHUNK_SIZE)

func inside(cell: Vector2i) -> bool:
	return cell.x >= -COORD_LIMIT and cell.y >= -COORD_LIMIT and cell.x < COORD_LIMIT and cell.y < COORD_LIMIT

func index_of(cell: Vector2i) -> int:
	return cell.y * width + cell.x

func terrain_at(cell: Vector2i) -> int:
	var chunk: Dictionary = regions.get_region(self, chunk_of(cell))
	return Terrain.WATER if chunk.is_empty() else int(chunk.tiles[local_index(cell)])

func _grow(chunk: Dictionary) -> void:
	var amount: int = regrowth - chunk.epoch
	if amount <= 0: return
	var coord: Vector2i = chunk.get("coord", Vector2i.ZERO)
	var ordinary: bool = climate.mode == "uniform" and climate.biome == 0 and biome_overrides.is_empty()
	for i in chunk.food.size():
		var cell := coord * CHUNK_SIZE + Vector2i(i % CHUNK_SIZE, i / CHUNK_SIZE)
		chunk.food[i] = mini(chunk.food[i] + (amount if ordinary else WorldClimate.growth_delta(self, cell, int(chunk.epoch), regrowth)), capacity(chunk.tiles[i]))
	chunk.epoch = regrowth

func food_at(cell: Vector2i) -> int:
	var chunk: Dictionary = regions.get_region(self, chunk_of(cell))
	if chunk.is_empty(): return 0
	var index := local_index(cell)
	return mini(int(chunk.food[index]) + WorldClimate.growth_delta(self, cell, int(chunk.epoch), regrowth), capacity(chunk.tiles[index]))

func _set_food(cell: Vector2i, value: int) -> void:
	var chunk: Dictionary = regions.get_region(self, chunk_of(cell))
	if chunk.is_empty(): return
	_grow(chunk)
	chunk.food[local_index(cell)] = value

func _set_terrain(cell: Vector2i, terrain: int) -> void:
	if regions.failed: return
	var key := chunk_of(cell)
	if regions.cold.has(key): regions.get_region(self, key)
	if not chunks.has(key):
		if terrain == Terrain.WATER: return
		var ground := PackedInt32Array()
		ground.resize(CHUNK_SIZE * CHUNK_SIZE)
		var resources := ground.duplicate()
		chunks[key] = {"tiles": ground, "food": resources, "wood": resources.duplicate(), "epoch": regrowth, "coord": key}
		region_key_count = -1
	var chunk: Dictionary = chunks[key]
	_grow(chunk)
	var previous: int = chunk.tiles[local_index(cell)]
	if terrain in [Terrain.WATER,Terrain.MOUNTAIN]: landscape.clear_cell(cell,key)
	chunk.tiles[local_index(cell)] = terrain
	chunk.food[local_index(cell)] = capacity(terrain)
	chunk.wood[local_index(cell)] = 12 if terrain == Terrain.FOREST else 0
	if previous == terrain:
		WorldExploration.invalidate(self,cell)
		return

	if previous != terrain and (previous in [Terrain.WATER, Terrain.MOUNTAIN] or terrain in [Terrain.WATER, Terrain.MOUNTAIN]):
		if (previous in [Terrain.GRASS,Terrain.SAND,Terrain.FOREST]) != (terrain in [Terrain.GRASS,Terrain.SAND,Terrain.FOREST]): path_revision += 1
		var retired := {}
		for id in navigation:
			var nav: Dictionary = navigation[id]
			if nav.has("origin") and absi(cell.x-nav.origin.x)+absi(cell.y-nav.origin.y) > int(nav.reach)+1: continue
			retired[id] = nav
		if not retired.is_empty():
			for id in retired: navigation.erase(id)
			navigation_cleanup.append(WorldNavigationCleanupJob.new(retired))
	else:
		for nav in navigation.values():
			if not nav.parents.has(cell): continue
			for field in ["food", "wood"]:
				var was_source: bool = previous in [Terrain.GRASS, Terrain.FOREST] if field == "food" else previous == Terrain.FOREST
				var is_source: bool = terrain in [Terrain.GRASS, Terrain.FOREST] if field == "food" else terrain == Terrain.FOREST
				if was_source == is_source: continue
				if not is_source: nav[field].erase(cell)
				else:
					var index: int = int(nav.order[cell])
					var first := 0
					var last: int = nav[field].size()
					while first < last:
						var mid := (first + last) / 2
						if int(nav.order[nav[field][mid]]) < index: first = mid + 1
						else: last = mid
					nav[field].insert(first, cell)
	if (previous == Terrain.WATER) != (terrain == Terrain.WATER):
		sea_revision += 1
		sea_routes.clear()
	if previous == Terrain.WATER and terrain != Terrain.WATER and not bounds_dirty.has(key):
		var point := Rect2i(cell, Vector2i.ONE)
		region_bounds[key] = region_bounds[key].merge(point) if region_bounds.has(key) else point
	elif previous != Terrain.WATER and terrain == Terrain.WATER:
		bounds_dirty[key] = true
	revision += 1
	WorldExploration.invalidate(self, cell)

	for dy in range(-1, 2):
		for dx in range(-1, 2): revisions[key + Vector2i(dx, dy)] = revision

func reclaim_navigation(budget_usec: int = 300) -> void:
	var deadline := Time.get_ticks_usec()+budget_usec
	while not navigation_cleanup.is_empty():
		var job: WorldNavigationCleanupJob = navigation_cleanup[0]
		job.unit()
		if job.finished: navigation_cleanup.pop_front()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break

func wood_at(cell: Vector2i) -> int:
	var chunk: Dictionary = regions.get_region(self, chunk_of(cell))
	return 0 if chunk.is_empty() else int(chunk.wood[local_index(cell)])

func harvest_wood(cell: Vector2i, amount: int) -> void:
	var chunk: Dictionary = regions.get_region(self, chunk_of(cell))
	if chunk.is_empty(): return
	var index := local_index(cell)
	chunk.wood[index] = maxi(0, int(chunk.wood[index]) - amount)
	if chunk.wood[index] == 0 and chunk.tiles[index] == Terrain.FOREST:
		var existing_food := mini(food_at(cell), capacity(Terrain.GRASS))
		_set_terrain(cell, Terrain.GRASS)
		_set_food(cell, existing_food)
		if stumps.size() < 4096: stumps[cell] = ticks; landscape.site(cell,"stump")
		terrain_changed.emit()

func touch_terrain(cell: Vector2i, radius: int = 0, notify: bool = true) -> void:
	revision += 1
	var reach := radius+2
	var low := chunk_of(cell-Vector2i.ONE*reach)
	var high := chunk_of(cell+Vector2i.ONE*reach)
	var dirty := {}
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key := Vector2i(x,y)
			var origin := key*CHUNK_SIZE
			var nearest := Vector2i(clampi(cell.x,origin.x,origin.x+CHUNK_SIZE-1),clampi(cell.y,origin.y,origin.y+CHUNK_SIZE-1))
			if nearest.distance_squared_to(cell) > reach*reach: continue
			for dy in range(-1,2):
				for dx in range(-1,2): dirty[key+Vector2i(dx,dy)] = true
	for key in dirty: revisions[key] = revision
	if notify: terrain_changed.emit()

func day() -> int:
	return month()

func month() -> int:
	return ticks / WorldEconomy.DAY_TICKS + 1

func year() -> int:
	return ticks / (WorldEconomy.DAY_TICKS * WorldEconomy.DAYS_PER_YEAR) + 1

func building_at(cell: Vector2i) -> Dictionary:
	return WorldEconomy.at(self, cell)

func walkable(cell: Vector2i) -> bool:
	var ground := terrain_at(cell)
	return inside(cell) and ground != Terrain.MOUNTAIN and (ground != Terrain.WATER or networks.bridge_open(self,cell))

func land_bounds() -> Rect2i:
	for key in bounds_dirty.keys():
		if not chunks.has(key):
			region_bounds.erase(key)
			continue
		var low := Vector2i(CHUNK_SIZE, CHUNK_SIZE)
		var high := Vector2i(-1, -1)
		var chunk: Dictionary = chunks[key]
		for i in chunk.tiles.size():
			if chunk.tiles[i] == Terrain.WATER: continue
			var cell := Vector2i(i % CHUNK_SIZE, i / CHUNK_SIZE)
			low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
			high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
		if high.x < low.x: region_bounds.erase(key)
		else: region_bounds[key] = Rect2i(key * CHUNK_SIZE + low, high - low + Vector2i.ONE)
	bounds_dirty.clear()
	var result := Rect2i()
	for bounds in region_bounds.values(): result = bounds if not result.has_area() else result.merge(bounds)
	return result if result.has_area() else Rect2i(Vector2i.ZERO, Vector2i(MAP_SIZE, MAP_SIZE))

func capacity(terrain: int) -> int:
	return 8 if terrain == Terrain.FOREST else (4 if terrain == Terrain.GRASS else 0)

func cells_in_brush(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if inside(cell) and cell.distance_squared_to(center) <= radius * radius:
				result.append(cell)
	return result

func paint(center: Vector2i, radius: int, terrain: int) -> bool:
	if regions.failed: return false
	if terrain < Terrain.WATER or terrain > Terrain.MOUNTAIN or radius < 0 or radius > 64 or not inside(center):
		return false
	var cells := cells_in_brush(center, radius)
	var needed := {}
	if terrain != Terrain.WATER:
		for cell in cells:
			var key := chunk_of(cell)
			if not has_region(key): needed[key] = true
	if region_count() + needed.size() > MAX_CHUNKS: return false
	for cell in cells:
		_set_terrain(cell, terrain)
		erase_fire(cell)

	var touched := {}
	for cell in cells: touched[chunk_of(cell)] = true
	for key in touched:
		if chunks.has(key) and chunks[key].tiles.count(Terrain.WATER) == CHUNK_SIZE * CHUNK_SIZE:
			chunks.erase(key)
			region_key_count = -1
	var repair := WorldTerrainRepairJob.new(self)
	while not repair.finished: repair.unit()
	regions.trim(self)
	terrain_changed.emit()
	changed.emit()
	return true

func nearest_land(origin: Vector2i, radius: int) -> Vector2i:
	if walkable(origin):
		return origin
	for r in range(1, radius + 1):
		for y in range(origin.y - r, origin.y + r + 1):
			for x in range(origin.x - r, origin.x + r + 1):
				if abs(x - origin.x) != r and abs(y - origin.y) != r:
					continue
				var cell := Vector2i(x, y)
				if walkable(cell):
					return cell
	return NO_CELL

func add_person(cell: Vector2i, announce: bool = true) -> bool:
	if not walkable(cell) or people.size() >= MAX_PEOPLE:
		return false
	var person := {"id": next_id, "x": cell.x, "y": cell.y, "hunger": 0.0, "age": 0, "home": -1}
	WorldEconomy.person_defaults(self, person)
	WorldLife.defaults(self, person)
	metrics.spawn_food += person.rations
	people.append(person)
	person_index[person.id] = person
	population.ready = false
	workforce.plans.clear(); workforce.contributions.clear(); workforce.shipments.clear()
	life_dirty = true
	population_dirty = true
	next_id += 1
	if announce:
		log_event("Новый житель", "На острове появился житель №%d." % (next_id - 1))
	changed.emit()
	return true

func remove_person(person_index_value: int, cause: String) -> void:
	if person_index_value < 0 or person_index_value >= people.size(): return
	var member: Dictionary = people[person_index_value]
	if removal_ids.has(member.id): return
	var job := WorldPersonRemovalJob.new(self,member,cause)
	if stepping:
		removal_ids[member.id] = true; person_removals.append(job)
	else:
		while not job.finished: job.unit()

func populate_demo() -> void:
	var spawn := nearest_land(Vector2i(width / 2, height / 2), 40)
	if spawn == NO_CELL:
		return
	for offset in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2), Vector2i(-1, -1), Vector2i(1, 1)]:
		add_person(nearest_land(spawn + offset, 8), false)
	log_event("Первые поселенцы", "Шесть жителей ищут место для нового дома.")
	changed.emit()

func set_fire(cell: Vector2i, ttl: int = 0) -> void:
	if not fires.has(cell):
		var key := chunk_of(cell)
		if not fire_regions.has(key): fire_regions[key] = {}
		fire_regions[key][cell] = true
		fire_revision += 1
	fires[cell] = ttl if ttl > 0 else (FOREST_FIRE_TICKS if terrain_at(cell) == Terrain.FOREST else GRASS_FIRE_TICKS)

func erase_fire(cell: Vector2i) -> void:
	if not fires.has(cell): return
	fires.erase(cell)
	var key := chunk_of(cell)
	if fire_regions.has(key):
		fire_regions[key].erase(cell)
		if fire_regions[key].is_empty(): fire_regions.erase(key)
	fire_revision += 1

func ignite(center: Vector2i, radius: int) -> void:
	var started := false
	for cell in cells_in_brush(center, radius):
		if terrain_at(cell) == Terrain.FOREST or terrain_at(cell) == Terrain.GRASS:
			set_fire(cell)
			started = true
	if started:
		site_cache.clear()
		log_event("Удар молнии", "Загорелась земля. Дождь может остановить огонь.")
	changed.emit()

func rain(center: Vector2i, radius: int) -> void:
	site_cache.clear()
	for cell in cells_in_brush(center, radius):
		erase_fire(cell)
		_set_food(cell, capacity(terrain_at(cell)))
	wet_until = ticks + RAIN_TICKS
	drought_until = 0
	log_event("Живительный дождь", "Огонь погас, запасы еды на земле восстановились.")
	changed.emit()

func step() -> void:
	var job := WorldStepJob.new(self)
	job.advance(0)

func track_person_move(member: Dictionary, previous: Vector2i) -> void:
	landscape.moved(self,member,previous)
	heritage.visit(self,member,Vector2i(member.x,member.y))
	heritage.returned(self,member)
	if chunk_of(previous) != chunk_of(Vector2i(member.x, member.y)): regions.pin_signature.clear()
	population.moved(self, member)
	workforce.moved(self, member, previous)

func _repair_buildings() -> void:
	var job := WorldBuildingRepairJob.new(self)
	while not job.finished: job.unit()

func repair_building(i: int, lost_stores: Dictionary) -> void:
	var value := buildings[i]
	var rect := WorldEconomy.footprint(value)
	var valid := not WorldEconomy.town(self, value.town).is_empty()
	var burning := false
	for y in rect.size.y:
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			if not walkable(cell): valid = false
			if fires.has(cell): burning = true
	if value.kind == "bridge" and value.ready and not networks.bridge_open(self,Vector2i(value.project_cells[0][0],value.project_cells[0][1])): valid = false
	if burning: value.integrity -= 2
	if valid and value.integrity > 0: return
	heritage.remember_building(self,value)
	if value.kind=="bridge" and value.ready: bridge_repair_needed = true
	networks.removed(self,value)
	metrics.lost_food += value.stock
	WorldCivilization.lost_building(self, value)
	if not value.ready: metrics.lost_wood += value.delivered
	if value.kind == "store" and value.ready: lost_stores[value.town] = true
	log_event("Постройка утрачена", "%s: %s." % [WorldEconomy.NAMES[value.kind], "пожар" if burning else "земля стала непригодной"])
	for y in rect.size.y:
		for x in rect.size.x: occupied.erase(rect.position + Vector2i(x, y))
	building_index.erase(value.id)
	for family in households:
		if family.dwelling == value.id:
			family.dwelling = -1
			metrics.lost_food += family.food
			family.food = 0
	life_dirty = true
	workforce.building_removed(value)
	landscape.building(self,value,false)
	if value.ready and walkable(Vector2i(value.x,value.y)): landscape.scar(self,Vector2i(value.x,value.y),"ruin",int(WorldEconomy.SIZE[value.kind]))
	buildings.remove_at(i)
	WorldSociety.invalidate(self)
	touch_terrain(Vector2i(value.x, value.y), int(WorldEconomy.SIZE[value.kind]))

func repair_storage(home: Dictionary, lost_stores: Dictionary) -> void:
	if not lost_stores.has(home.id): return
	var food_loss := maxi(0, int(home.food) - WorldEconomy.food_capacity(self, home))
	var wood_loss := maxi(0, int(home.wood) - WorldEconomy.wood_capacity(self, home))
	home.food -= food_loss
	home.wood -= wood_loss
	metrics.lost_food += food_loss
	metrics.lost_wood += wood_loss
	if food_loss + wood_loss > 0:
		log_event("Потеря запасов", "%s: со складом утрачено %d еды и %d древесины." % [home.name, food_loss, wood_loss])

func _town_near(cell: Vector2i, radius: int) -> Dictionary:
	var best: Dictionary = {}
	var distance := float(radius)
	for town in towns:
		var d := cell.distance_to(Vector2i(town.x, town.y))
		if d < distance and WorldEconomy.navigation(self, town).parents.has(cell):
			best = town
			distance = d
	return best

func _found_towns() -> void:
	for person in people: _found_town(person)

func _found_town(p: Dictionary) -> void:
	if WorldTravel.away(self,p.id): return
	if not WorldLife.adult(self, p): return
	var cell := Vector2i(p.x, p.y)
	if p.home != -1: return
	if not _town_near(cell, 28).is_empty():
		return
	var nearby: Array[Dictionary] = []
	nearby = population.nearby(self, cell, 143)
	if nearby.size() < 3: return
	var neighbors := 0
	var probe := {"id": -p.id, "x": cell.x, "y": cell.y}
	var prepared_navigation: Dictionary = WorldEconomy.navigation(self, probe)
	var parents: Dictionary = prepared_navigation.parents
	for other in nearby:
		if parents.has(Vector2i(other.x, other.y)): neighbors += 1
	navigation.erase(probe.id)
	if neighbors >= 3:
		var name_value := WorldSettlementIdentity.name_for(self, cell, prepared_navigation)
		var home := {"id": next_id, "name": name_value, "x": cell.x, "y": cell.y, "food": 0, "wood": 0, "level": 1}
		next_id += 1
		towns.append(home)
		navigation[home.id] = prepared_navigation
		heritage.settled(self,home)
		WorldEconomy.add_building(self, home, "camp", cell, true)
		log_event("Основано поселение", "%s: жители обустроили общий лагерь." % name_value)


func _step_fire() -> bool:
	var job := WorldFireStepJob.new(self)
	while not job.finished: job.unit()
	return job.dirty

func _random_event() -> void:
	WorldWeather.schedule(self)

func log_event(title: String, message: String) -> void:
	history_revision += 1
	history.push_front({"tick": ticks, "title": title, "message": message})
	if history.size() > 60:
		history.resize(60)

func to_dict(include_regions: bool = true, include_residents: bool = true) -> Dictionary:
	var saved_regions: Array[Dictionary] = []
	var keys := region_keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key in keys if include_regions else []:
		var chunk: Dictionary = regions.snapshot(self, key)
		if chunk.is_empty(): return {}
		saved_regions.append({"x": key.x, "y": key.y, "tiles": Array(chunk.tiles), "food": Array(chunk.food), "wood": Array(chunk.wood), "epoch": chunk.epoch})
	var saved_fires: Array[Dictionary] = []
	for cell in fires: saved_fires.append({"x": cell.x, "y": cell.y, "ttl": fires[cell]})
	return {"version": SAVE_VERSION, "chunk_size": CHUNK_SIZE, "seed": world_seed,
		"climate": WorldClimate.save(self), "civilization": WorldCivilization.save(self), "maritime": WorldMaritime.save(self), "journeys": journeys.duplicate(true),
		"ticks": ticks, "next_id": next_id, "chunks": saved_regions, "regrowth": regrowth,
		"people": people.duplicate(true) if include_residents else [], "towns": towns.duplicate(true), "buildings": buildings.duplicate(true), "metrics": metrics.duplicate(), "fires": saved_fires,
		"societies": societies.duplicate(true), "households": households.duplicate(true), "ancestry_archive": ancestry_archive.duplicate(true),
		"history": history.duplicate(true), "rng_state": str(rng.state), "landscape":landscape.save(), "heritage":heritage.save(), "networks":networks.save(),
		"wet_until": wet_until, "drought_until": drought_until, "weather": weather.duplicate(true)}

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value))

static func _migrate(data: Dictionary) -> Dictionary:
	if data.get("width") != MAP_SIZE or data.get("height") != MAP_SIZE: return {}
	if not data.get("tiles") is Array or not data.get("food") is Array: return {}
	if data.tiles.size() != MAP_SIZE * MAP_SIZE or data.food.size() != MAP_SIZE * MAP_SIZE or not data.get("fires") is Dictionary: return {}
	var result := data.duplicate(true)
	result.version = 2
	result.chunk_size = CHUNK_SIZE
	result.regrowth = 0
	result.chunks = []
	for cy in MAP_SIZE / CHUNK_SIZE:
		for cx in MAP_SIZE / CHUNK_SIZE:
			var region := {"x": cx, "y": cy, "tiles": [], "food": [], "epoch": 0}
			for y in CHUNK_SIZE:
				for x in CHUNK_SIZE:
					var index := (cy * CHUNK_SIZE + y) * MAP_SIZE + cx * CHUNK_SIZE + x
					region.tiles.append(data.tiles[index])
					region.food.append(data.food[index])
			result.chunks.append(region)
	result.fires = []
	for key in data.fires:
		if not str(key).is_valid_int(): return {}
		var index := int(key)
		if index < 0 or index >= MAP_SIZE * MAP_SIZE: return {}
		result.fires.append({"x": index % MAP_SIZE, "y": index / MAP_SIZE, "ttl": data.fires[key]})
	for collection in ["people", "towns"]:
		if not data.get(collection) is Array: return {}
		for entity in data[collection]:
			if not entity is Dictionary or not _integer(entity.get("x")) or not _integer(entity.get("y")): return {}
			if entity.x < 0 or entity.y < 0 or entity.x >= MAP_SIZE or entity.y >= MAP_SIZE: return {}
	for key in ["width", "height", "tiles", "food"]: result.erase(key)
	return result

static func from_dict(source: Dictionary, region_files: Dictionary = {}) -> WorldState:
	var data := _migrate(source) if source.get("version") == 1 else source
	if not _integer(data.get("version")) or int(data.version) not in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, SAVE_VERSION] or data.get("chunk_size") != CHUNK_SIZE: return null
	for key in ["chunks", "people", "towns", "history", "fires"]:
		if not data.get(key) is Array: return null
	if data.chunks.size() > MAX_CHUNKS or data.people.size() > MAX_PEOPLE or data.towns.size() > MAX_PEOPLE or data.history.size() > 60: return null
	for key in ["seed", "ticks", "next_id", "wet_until", "drought_until", "regrowth"]:
		if not _integer(data.get(key)): return null
	if data.ticks < 0 or data.next_id <= 0 or data.regrowth < 0 or data.regrowth > int(data.ticks) / 20: return null
	if not data.get("rng_state") is String or not data.rng_state.is_valid_int(): return null
	var world := WorldState.new()
	world.regrowth = int(data.regrowth)
	for reference in data.chunks:
		var region: Variant = reference
		if reference is Dictionary and _integer(reference.get("x")) and _integer(reference.get("y")):
			var key := Vector2i(reference.x, reference.y)
			if region_files.has(key):
				if FileAccess.get_sha256(region_files[key].path) != region_files[key].hash: return null
				region = SaveStore._read_json(region_files[key].path, SaveStore.MAX_REGION_BYTES)
				if region.get("x") != reference.x or region.get("y") != reference.y: return null
		if not region is Dictionary: return null
		for key in ["x", "y", "epoch"]:
			if not _integer(region.get(key)): return null
		if region.epoch < 0 or region.epoch > data.regrowth: return null
		var coord := Vector2i(region.x, region.y)
		if not world.inside(coord * CHUNK_SIZE) or world.has_region(coord): return null
		if not region.get("tiles") is Array or not region.get("food") is Array: return null
		if region.tiles.size() != CHUNK_SIZE * CHUNK_SIZE or region.food.size() != CHUNK_SIZE * CHUNK_SIZE: return null
		var ground_low := Vector2i(CHUNK_SIZE, CHUNK_SIZE)
		var ground_high := Vector2i(-1, -1)
		for i in region.tiles.size():
			if not _integer(region.tiles[i]) or region.tiles[i] < 0 or region.tiles[i] > Terrain.MOUNTAIN: return null
			if not _integer(region.food[i]) or region.food[i] < 0 or region.food[i] > world.capacity(int(region.tiles[i])): return null
			if region.tiles[i] != Terrain.WATER:
				var point := Vector2i(i % CHUNK_SIZE, i / CHUNK_SIZE)
				ground_low.x = mini(ground_low.x, point.x); ground_low.y = mini(ground_low.y, point.y)
				ground_high.x = maxi(ground_high.x, point.x); ground_high.y = maxi(ground_high.y, point.y)
		if ground_high.x >= 0: world.region_bounds[coord] = Rect2i(coord * CHUNK_SIZE + ground_low, ground_high - ground_low + Vector2i.ONE)
		var timber := PackedInt32Array()
		if data.version >= 3:
			if not region.get("wood") is Array or region.wood.size() != CHUNK_SIZE * CHUNK_SIZE: return null
			for i in region.wood.size():
				if not _integer(region.wood[i]) or region.wood[i] < 0 or region.wood[i] > (12 if region.tiles[i] == Terrain.FOREST else 0): return null
				timber.append(int(region.wood[i]))
		else:
			for ground in region.tiles: timber.append(12 if ground == Terrain.FOREST else 0)
		world.chunks[coord] = {"tiles": PackedInt32Array(region.tiles), "food": PackedInt32Array(region.food), "wood": timber, "epoch": int(region.epoch), "coord": coord}
		if world.chunks.size() > WorldRegions.CACHE_LIMIT * 2: world.regions.trim(world)
	if not world.networks.prepare_bridges(world,data.get("buildings",[])): return null
	var used_ids := {}
	for collection in ["people", "towns"]:
		for entity in data[collection]:
			if not entity is Dictionary: return null
			var integers := ["id", "x", "y", "age", "home"] if collection == "people" else ["id", "x", "y", "food", "wood", "level"]
			for key in integers:
				if not _integer(entity.get(key)): return null
			if used_ids.has(int(entity.id)) or entity.id <= 0: return null
			if not world.walkable(Vector2i(entity.x, entity.y)) and not (collection == "people" and WorldMaritime.saved_onboard(data, entity.id)): return null
			used_ids[int(entity.id)] = true
			if collection == "people":
				if not (entity.get("hunger") is int or entity.get("hunger") is float): return null
				if not is_finite(float(entity.hunger)) or entity.hunger < 0 or entity.hunger > 100 or entity.age < 0: return null
			elif not entity.get("name") is String or entity.level < 1 or entity.level > 3 or entity.food < 0 or entity.wood < 0: return null
			var restored: Dictionary = entity.duplicate()
			for key in integers: restored[key] = int(restored[key])
			world[collection].append(restored)
	for id in used_ids:
		if id >= data.next_id: return null
	for fire in data.fires:
		if not fire is Dictionary: return null
		for key in ["x", "y", "ttl"]:
			if not _integer(fire.get(key)): return null
		var cell := Vector2i(fire.x, fire.y)
		if not world.inside(cell) or world.fires.has(cell) or fire.ttl < 1 or fire.ttl > 24: return null
		if world.terrain_at(cell) not in [Terrain.GRASS, Terrain.FOREST]: return null
		world.set_fire(cell,int(fire.ttl))
	for event in data.history:
		if not event is Dictionary or not event.get("title") is String or not event.get("message") is String or not _integer(event.get("tick")): return null
		var restored: Dictionary = event.duplicate()
		restored.tick = int(restored.tick)
		world.history.append(restored)
	world.world_seed = int(data.seed)
	world.ticks = int(data.ticks)
	world.next_id = int(data.next_id)
	world.wet_until = int(data.wet_until)
	world.drought_until = int(data.drought_until)
	world.rng.seed = world.world_seed
	world.rng.state = data.rng_state.to_int()
	if data.version == 2:
		for person in world.people:
			WorldEconomy.person_defaults(world, person)
			person.rations = 0
			if WorldEconomy.town(world, person.home).is_empty(): person.home = -1
		for home in world.towns:
			WorldEconomy.add_building(world, home, "camp", Vector2i(home.x, home.y), true)
			for i in maxi(1, home.level - 1):
				var cell := WorldEconomy.site(world, home, "house")
				if cell != NO_CELL: WorldEconomy.add_building(world, home, "house", cell, true)
		world.log_event("Хозяйство обновлено", "Запасы сохранены. Жители освоят добычу, переноску и строительство.")
		world.navigation.clear()
	elif not WorldEconomy.restore(world, data): return null
	for person in world.people: world.person_index[person.id] = person
	if data.version < 4:
		for person in world.people:

			var previous_name: String = person.name
			WorldLife.defaults(world, person)
			person.name = previous_name
		WorldLife.reconcile(world)
		world.log_event("Жизнь поколений", "Жители сохранили свои запасы и работу. Теперь у них есть возраст и семьи.")
	elif not WorldLife.restore(world, data): return null
	if data.version<7:
		for member in world.people: member.rivals=[]
	if data.version < 5:
		for member in world.people: WorldSocial.defaults(world, member)
		for record in world.ancestry_archive: record.skills = {"food": 0, "wood": 0, "build": 0, "farm": 0}
	elif not WorldSocial.restore(world): return null
	if data.version < 6:
		for member in world.people: member.ideas = []
		for home in world.towns: WorldSociety.ensure_town(world, home)
	elif not WorldSociety.restore(world, data): return null
	if data.version < 7:
		for value in world.buildings: WorldCivilization.material_defaults(value)
		for home in world.towns: WorldCivilization.ensure(world, home)
	elif not WorldClimate.restore(world, data.get("climate")) or not WorldCivilization.restore(world, data.get("civilization")) or not WorldMaritime.restore(world, data.get("maritime")) or not WorldTravel.restore(world, data.get("journeys")): return null
	if not WorldWeather.restore(world, data.get("weather")): return null
	if data.version >= 11 and not data.has("landscape"): return null
	if not world.landscape.restore(world,data.get("landscape")): return null
	if data.version >= 12 and not data.get("heritage") is Dictionary: return null
	if not world.heritage.restore(world,data.get("heritage")): return null
	if data.version>=13 and not data.get("networks") is Dictionary: return null
	if not world.networks.restore(world,data.get("networks")): return null
	return world

func _profile_stage(label: String, before: int) -> int:
	if not profiling: return before
	var now:=Time.get_ticks_usec()
	timings[label]=int(timings.get(label,0))+now-before
	return now
