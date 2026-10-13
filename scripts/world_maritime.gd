class_name WorldMaritime
extends RefCounted

const MAX_VOYAGES := 32
const MAX_CONTACTS := 512
const SPEED := {"boat": 4, "sailboat": 1024}
const HOLD := {"boat": 12, "sailboat": 120}

static func onboard(world, id: int) -> bool:
	return world.voyage_people.has(id)

static func saved_onboard(data: Dictionary, id: int) -> bool:
	if not data.get("maritime") is Dictionary or not data.maritime.get("voyages") is Array: return false
	for ship in data.maritime.voyages:
		if not ship is Dictionary or not ship.get("crew") is Array: continue
		for member in ship.crew:
			if WorldState._integer(member) and int(member) == id: return true
	return false

static func shore(world, home: Dictionary, toward: Vector2i) -> Dictionary:
	var best := INF
	var result := {}
	for coast in WorldEconomy.navigation(world,home).coasts:
		var point: Vector2i=coast.land
		var water: Vector2i=coast.water
		if world.fires.has(point): continue
		var distance:=water.distance_squared_to(toward)
		if distance<best:
			best=distance
			result={"land":point,"water":water}
	return result

static func contact(world, a: int, b: int) -> Dictionary:
	for value in world.contacts:
		if (value.a == a and value.b == b) or (value.a == b and value.b == a): return value
	return {}

static func meet(world, home: Dictionary, target: Dictionary, carriers: Array) -> void:
	if home.is_empty() or target.is_empty() or home.id == target.id: return
	var value := contact(world, home.id, target.id)
	if value.is_empty():
		if world.contacts.size() >= MAX_CONTACTS: return
		value = {"a": int(home.id), "b": int(target.id), "tick": world.ticks, "visits": 0, "trust": 0}
		world.contacts.append(value)
		world.log_event("Первый контакт", "%s встретило жителей %s. Открыт путь для обмена и переселения." % [home.name, target.name])
	value.visits += 1
	value.trust = mini(100, int(value.trust) + 5)
	var theirs := WorldSociety.get_society(world, target.id)
	for id in carriers:
		var member := WorldLife.person(world, id)
		if member.is_empty(): continue
		for key in member.ideas:
			if not theirs.tech[key].known:
				theirs.tech[key].known = true
				world.log_event("Знание с другого берега", "%s: путешественник рассказал об идее «%s». Её предстоит освоить на месте." % [target.name, WorldSociety.TECH[key].name])
				break
		for key in WorldSociety.TECH:
			if theirs.tech[key].mastered:
				WorldSociety.remember(member, key)
				break

static func segment_clear(world, a: Vector2i, b: Vector2i) -> bool:
	var job := WorldSeaSegmentJob.new(world, a, b)
	while not job.finished: job.unit()
	return job.clear

static func route(world, a: Vector2i, b: Vector2i) -> Array:
	var job := WorldSeaRouteJob.new(world, a, b)
	job.advance(0)
	return job.result

static func route_length(points: Array) -> float:
	var length := 0.0
	for i in range(1, points.size()): length += Vector2(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]).length()
	return length

static func position(ship: Dictionary) -> Vector2i:
	if ship.phase in ["boarding", "unload"]: return Vector2i(ship.origin[0], ship.origin[1])
	var total := route_length(ship.route)
	var remaining: float = total * float(ship.progress) / maxi(1, int(ship.duration))
	var points: Array = ship.route if ship.phase == "outbound" else ship.route.duplicate()
	if ship.phase == "returning": points.reverse()
	for i in range(1, points.size()):
		var a := Vector2(points[i - 1][0], points[i - 1][1])
		var b := Vector2(points[i][0], points[i][1])
		var length := a.distance_to(b)
		if remaining <= length: return Vector2i(a.lerp(b, remaining / maxf(1, length)).round())
		remaining -= length
	return Vector2i(points.back()[0], points.back()[1])

static func fish_assign(world, member: Dictionary, home: Dictionary) -> bool:
	var basic := not WorldSociety.mastered(world, home, "carpentry")
	var limit := 2 if basic else 6
	var coast: Dictionary = world.workforce.fishing_coast(world, home, limit)
	if coast.is_empty(): return false
	var point: Vector2i = coast.land
	var water: Vector2i = coast.water
	WorldEconomy.set_task(world, member, WorldEconomy.task("fish", point))
	member.task.water_x = water.x; member.task.water_y = water.y
	if basic: member.task.basic = true
	member.job = "fisher"
	return true

static func fish(world, member: Dictionary, home: Dictionary) -> void:
	var task: Dictionary = member.task
	var point := Vector2i(task.x, task.y)
	var water := Vector2i(task.water_x, task.water_y)
	if world.terrain_at(water) != WorldState.Terrain.WATER or world.fires.has(point) or not world.walkable(point):
		WorldEconomy.set_task(world, member, {})
		return
	if not WorldEconomy.move(world, member, point, home): return
	task.work += WorldSocial.work_credit(world, member, "food")
	WorldSocial.practice(world, member, "food")
	var basic: bool = task.get("basic", false)
	if task.work < (10 if basic else 5): return
	var usage: Dictionary = world.fishing.get(water, {})
	if usage.get("day", -1) != world.ticks / WorldEconomy.DAY_TICKS: usage = {"day": world.ticks / WorldEconomy.DAY_TICKS, "amount": 0}
	var amount: int = mini(1 if basic else 3, maxi(0, (2 if basic else 6) - int(usage.amount)))
	usage.amount += amount
	world.fishing[water] = usage
	member.cargo = amount
	member.cargo_kind = "food" if amount > 0 else ""
	world.metrics.harvested_food += amount
	WorldEconomy.set_task(world, member, {})

static func survival(world, member: Dictionary) -> bool:
	var home := {"id": -int(member.id), "x": int(member.x), "y": int(member.y)}
	if member.task.get("kind", "") == "fish":
		fish(world, member, home)
		return true
	if member.rations > 0 or member.cargo > 0 or member.hunger < WorldEconomy.NUTRITION: return false
	var point := Vector2i(member.x, member.y)
	if world.claims.has("fish:%d:%d" % [point.x, point.y]): return false
	for direction in WorldState.DIRECTIONS:
		var neighbor: Vector2i = point + direction
		if world.walkable(neighbor) and not world.fires.has(neighbor) and world.food_at(neighbor) > 0: return false
	for direction in WorldState.DIRECTIONS:
		var water: Vector2i = point + direction
		if world.terrain_at(water) != WorldState.Terrain.WATER: continue
		var used: Dictionary = world.fishing.get(water, {})
		if used.get("day", -1) == world.ticks / WorldEconomy.DAY_TICKS and used.get("amount", 0) >= 2: continue
		var task := WorldEconomy.task("fish", point)
		task.water_x = water.x; task.water_y = water.y; task.basic = true
		WorldEconomy.set_task(world, member, task)
		member.job = "fisher"
		fish(world, member, home)
		return true
	return false

static func crew_candidates(world, home: Dictionary, count: int) -> Array:
	var crew: Array = []
	if WorldEconomy.members(world,home).size() < count+3: return crew
	for member in WorldEconomy.members(world,home):
		if not WorldLife.adult(world,member) or WorldTravel.away(world,member.id) or member.cargo > 0 or member.energy < 40 or member.hunger >= 25 or member.birth_due >= 0 or member.health < 70: continue
		if member.task.get("kind","") in ["care","teach","research"] or not WorldLife.care_candidate(world,member).is_empty(): continue
		crew.append(int(member.id))
		if crew.size() == count: return crew
	return []

static func provisions(duration: int, count: int) -> int:
	return ceili((duration*2+60)*count*WorldEconomy.HUNGER_PER_STEP/WorldEconomy.NUTRITION)+4

static func can_supply(world, home: Dictionary, vessel: Dictionary, duration: int, count: int) -> bool:
	var amount := provisions(duration,count)
	return amount <= int(HOLD[vessel.kind]) and home.food-amount >= WorldEconomy.members(world,home).size()*3

static func launch(world, home: Dictionary, vessel: Dictionary, destination: Dictionary, purpose: String = "explore", prepared_route: Variant = null) -> bool:
	if world.voyages.size() >= MAX_VOYAGES or not vessel.ready or WorldEconomy.food_days(world, home) < 10: return false
	for ship in world.voyages:
		if ship.home == home.id: return false
	var landing: Vector2i = destination.land
	var departure := shore(world, home, landing)
	if departure.is_empty(): return false
	var count := 3 if purpose == "colony" else 1
	var crew := crew_candidates(world,home,count)
	if crew.size() != count: return false
	var minimum_duration := maxi(20,ceili(departure.water.distance_to(destination.water)/int(SPEED[vessel.kind])))
	if not can_supply(world,home,vessel,minimum_duration,count): return false
	var points: Array = route(world, departure.water, destination.water) if prepared_route == null else prepared_route
	if points.is_empty(): return false
	var duration: int = maxi(20, ceili(route_length(points) / int(SPEED[vessel.kind])))
	var provisions: int = provisions(duration,count)
	if not can_supply(world,home,vessel,duration,count): return false
	var ship := {"id": world.next_id, "home": int(home.id), "kind": vessel.kind, "crew": crew, "origin": [departure.land.x, departure.land.y], "landing": [landing.x, landing.y], "route": points, "phase": "boarding", "progress": 0, "duration": duration, "food": provisions, "cargo_kind": "", "cargo": 0, "purpose": purpose, "target": int(destination.get("town", -1)), "integrity": 12, "wait": 0}
	world.next_id += 1
	home.food -= provisions
	world.voyages.append(ship)
	world.voyage_index[ship.id] = ship
	for id in crew:
		world.voyage_people[id] = ship.id
		var member := WorldLife.person(world, id)
		WorldEconomy.set_task(world, member, WorldEconomy.task("travel", departure.land))
		member.job = "sailor"
		WorldSociety.remember(member, "sailing" if vessel.kind == "sailboat" else "navigation")
	if purpose == "trade":
		var stock: Dictionary = WorldCivilization.ensure(world, home).stock
		for key in WorldCivilization.GOODS:
			if stock[key] < 6: continue
			ship.cargo_kind = key
			ship.cargo = 3
			stock[key] -= 3
			break
	world.building_index.erase(vessel.id)
	for y in WorldEconomy.SIZE[vessel.kind]:
		for x in WorldEconomy.SIZE[vessel.kind]: world.occupied.erase(Vector2i(vessel.x + x, vessel.y + y))
	world.workforce.building_removed(vessel)
	world.buildings.erase(vessel)
	world.touch_terrain(Vector2i(vessel.x, vessel.y), WorldEconomy.SIZE[vessel.kind])
	WorldSociety.use(world, home, "sailing" if ship.kind == "sailboat" else "navigation")
	WorldSociety.invalidate(world)
	world.log_event("Экспедиция готовится", "%s: %s, %d участник%s и %d еды. Экипаж идёт к берегу." % [home.name, WorldEconomy.NAMES[ship.kind], count, "а" if count > 1 else "", provisions])
	return true

static func crew_step(world, member: Dictionary) -> void:
	var ship: Dictionary = world.voyage_index.get(world.voyage_people.get(member.id, -1), {})
	if ship.is_empty(): return
	if ship.phase == "boarding":
		var home := WorldEconomy.town(world, ship.home)
		if not home.is_empty(): WorldEconomy.move(world, member, Vector2i(ship.origin[0], ship.origin[1]), home)
	if member.hunger >= WorldEconomy.NUTRITION:
		if member.rations > 0:
			member.rations -= 1
			member.hunger -= WorldEconomy.NUTRITION
			world.metrics.eaten_food += 1
		elif ship.food > 0:
			ship.food -= 1
			member.hunger -= WorldEconomy.NUTRITION
			world.metrics.eaten_food += 1
	if member.hunger > 100: world.remove_person(world.people.find(member), "экспедиция осталась без снабжения")

static func death(world, id: int) -> void:
	var ship: Dictionary = world.voyage_index.get(world.voyage_people.get(id, -1), {})
	if not ship.is_empty(): ship.crew.erase(id)
	world.voyage_people.erase(id)

static func unload(world, ship: Dictionary) -> void:
	var home := WorldEconomy.town(world, ship.home)
	if home.is_empty():
		lose(world, ship)
		return
	var amount: int = mini(ship.food, WorldEconomy.food_capacity(world, home) - int(home.food))
	home.food += amount
	ship.food -= amount
	if ship.cargo > 0:
		var storage: Dictionary = home if ship.cargo_kind in ["food", "wood"] else WorldCivilization.ensure(world, home).stock
		var limit: int = WorldEconomy.food_capacity(world, home) if ship.cargo_kind == "food" else (WorldEconomy.wood_capacity(world, home) if ship.cargo_kind == "wood" else WorldCivilization.CAPACITY)
		amount = mini(ship.cargo, limit - int(storage[ship.cargo_kind]))
		storage[ship.cargo_kind] += amount
		ship.cargo -= amount
		if ship.cargo == 0: ship.cargo_kind = ""
	if ship.food == 0 and ship.cargo == 0:
		world.voyage_index.erase(ship.id)
		world.voyage_route_versions.erase(ship.id)
		world.voyages.erase(ship)

static func lose(world, ship: Dictionary) -> void:
	world.metrics.lost_food += int(ship.food) + (int(ship.cargo) if ship.cargo_kind == "food" else 0)
	world.metrics.lost_wood += int(ship.cargo) if ship.cargo_kind == "wood" else 0
	if WorldCivilization.GOODS.has(ship.cargo_kind): world.industry.lost[ship.cargo_kind] += int(ship.cargo)
	for id in ship.crew.duplicate():
		var member := WorldLife.person(world, id)
		if not member.is_empty(): world.remove_person(world.people.find(member), "корабль потерян в море")
	world.voyage_index.erase(ship.id)
	world.voyage_route_versions.erase(ship.id)
	world.voyages.erase(ship)
	world.log_event("Корабль потерян", "Экспедиция не вернулась. Учтена потеря экипажа и груза.")

static func land_crew(world, ship: Dictionary, home: Dictionary, cell: Vector2i) -> void:
	for id in ship.crew:
		var member := WorldLife.person(world, id)
		if member.is_empty(): continue
		member.x = cell.x
		member.y = cell.y
		member.home = int(home.id) if not home.is_empty() else -1
		WorldEconomy.set_task(world, member, {})
		member.job = "settler"
		world.voyage_people.erase(id)
	ship.crew = []
	world.population_dirty = true
	world.life_dirty = true
	WorldLife.reconcile(world)
	WorldSociety.invalidate(world)

static func arrive(world, ship: Dictionary) -> void:
	var landing := Vector2i(ship.landing[0], ship.landing[1])
	if not world.walkable(landing):
		ship.phase = "returning"
		ship.progress = 0
		world.log_event("Берег изменился", "Экспедиция возвращается: высадка стала невозможной.")
		return
	var home := WorldEconomy.town(world, ship.home)
	var target: Dictionary = world._town_near(landing, 28)
	if not target.is_empty():
		meet(world, home, target, ship.crew)
		if ship.purpose == "trade" and ship.cargo > 0 and WorldCivilization.GOODS.has(ship.cargo_kind):
			var stock: Dictionary = WorldCivilization.ensure(world, target).stock
			var amount: int = mini(ship.cargo, WorldCivilization.CAPACITY - int(stock[ship.cargo_kind]))
			if amount == ship.cargo and amount > 0 and target.food >= amount * 2 + 12:
				stock[ship.cargo_kind] += amount
				target.food -= amount * 2
				ship.cargo_kind = "food"
				ship.cargo = amount * 2
				world.log_event("Морской обмен", "%s обменяло материалы на %d еды у %s." % [home.name, ship.cargo, target.name])
		if ship.purpose == "migrate":
			land_crew(world, ship, target, landing)
			ship.home = int(target.id)
			ship.origin = [landing.x, landing.y]
	elif ship.purpose == "colony" and ship.crew.size() >= 3:
		var colony := {"id": world.next_id, "name": "Новый берег %d" % world.next_id, "x": landing.x, "y": landing.y, "food": 0, "wood": 0, "level": 1}
		world.next_id += 1
		world.towns.append(colony)
		WorldEconomy.add_building(world, colony, "camp", landing, true)
		land_crew(world, ship, colony, landing)
		colony.food = mini(ship.food, WorldEconomy.food_capacity(world, colony))
		ship.food -= int(colony.food)
		ship.home = int(colony.id)
		ship.origin = [landing.x, landing.y]
		meet(world, home, colony, [])
		world.log_event("Основана колония", "%s: переселенцы начали жизнь на новом материке." % colony.name)
	var mark := "%d:%d:%d" % [ship.home, landing.x, landing.y]
	if world.explored_coasts.size()>=8192 and not world.explored_coasts.has(mark): world.explored_coasts.erase(world.explored_coasts.keys()[0])
	world.explored_coasts[mark] = world.ticks
	if ship.crew.is_empty(): ship.phase = "unload"
	else: ship.phase = "returning"
	ship.progress = 0

static func step(world) -> void:
	var job := WorldMaritimeStepJob.new(world)
	while not job.finished: job.unit()

static func step_ship(world, ship: Dictionary) -> void:
	if ship.phase == "unload":
		unload(world, ship)
		return
	if ship.crew.is_empty():
		lose(world, ship)
		return
	if ship.phase == "boarding":
		var ready := true
		for id in ship.crew:
			var member := WorldLife.person(world, id)
			if member.is_empty() or Vector2i(member.x, member.y) != Vector2i(ship.origin[0], ship.origin[1]): ready = false
		if ready:
			ship.phase = "outbound"
			world.log_event("Выход в море", "Экспедиция покинула берег. Длина маршрута: %d клеток." % roundi(route_length(ship.route)))
		return
	if WorldWeather.at(world, position(ship), "storm"):
		ship.wait = maxi(int(ship.wait), 1)
		if world.ticks % (WorldEconomy.DAY_TICKS * (2 if ship.kind == "sailboat" else 1)) == 0: ship.integrity -= 1
	if ship.integrity <= 0:
		lose(world, ship)
		return
	if ship.wait > 0:
		ship.wait -= 1
		return
	ship.progress += 1
	if ship.progress < ship.duration: return
	if ship.phase == "outbound": arrive(world, ship)
	else:
		var cell: Vector2i = world.nearest_land(Vector2i(ship.origin[0], ship.origin[1]), 12)
		if cell == WorldState.NO_CELL:
			lose(world, ship)
			return
		var home := WorldEconomy.town(world, ship.home)
		land_crew(world, ship, home, cell)
		ship.phase = "unload"
		ship.progress = 0
		world.log_event("Экспедиция вернулась", "Мореплаватели вернулись с известиями и оставшимися запасами.")


static func daily(world) -> void:
	var job := WorldMaritimeDailyJob.new(world)
	while not job.finished: job.unit()

static func destination_priority(world, home: Dictionary, destination: Dictionary) -> int:
	if destination.get("town",-1)==home.id: return 3
	var known: bool=not contact(world,home.id,destination.get("town",-1)).is_empty()
	var mark: String="%d:%d:%d" % [home.id,destination.land.x,destination.land.y]
	if known or world.explored_coasts.has(mark): return 2
	return 0 if destination.get("town",-1)!=-1 else 1

static func description(world, home: Dictionary) -> String:
	var text := "\n\nМореплавание"
	var found := false
	for ship in world.voyages:
		if ship.home != home.id: continue
		found = true
		text += "\n%s · %s\nЭкипаж: %d · еда: %d · путь: %d%%" % [WorldEconomy.NAMES[ship.kind], {"boarding": "сбор экипажа", "outbound": "экспедиция", "returning": "возвращение", "unload": "разгрузка"}[ship.phase], ship.crew.size(), ship.food, ship.progress * 100 / maxi(1, int(ship.duration))]
	if not found: text += "\nВ море нет кораблей"
	for value in world.contacts:
		if home.id not in [value.a, value.b]: continue
		var target := WorldEconomy.town(world, value.b if value.a == home.id else value.a)
		if not target.is_empty(): text += "\nКонтакт: %s · встреч: %d" % [target.name, value.visits]
	return text

static func save(world) -> Dictionary:
	var fishing: Array = []
	for cell in world.fishing: fishing.append([cell.x, cell.y, world.fishing[cell].day, world.fishing[cell].amount])
	return {"voyages": world.voyages.duplicate(true), "contacts": world.contacts.duplicate(true), "explored": world.explored_coasts.duplicate(), "fishing": fishing}

static func restore(world, data: Variant) -> bool:
	for home in world.towns:
		if home.has("sea_search_cursor"):
			if not WorldState._integer(home.sea_search_cursor) or home.sea_search_cursor < 0 or home.sea_search_cursor >= WorldState.MAX_CHUNKS: return false
			home.sea_search_cursor = int(home.sea_search_cursor)
		if home.has("sea_route_cursor"):
			if not WorldState._integer(home.sea_route_cursor) or home.sea_route_cursor < 0 or home.sea_route_cursor > WorldState.MAX_PEOPLE+WorldMaritimeDailyJob.SEARCH_REGIONS: return false
			home.sea_route_cursor = int(home.sea_route_cursor)
	if not data is Dictionary or not data.get("voyages") is Array or data.voyages.size() > MAX_VOYAGES or not data.get("contacts") is Array or data.contacts.size() > MAX_CONTACTS or not data.get("explored") is Dictionary or data.explored.size() > 8192: return false
	var ids := {}
	for values in [world.people, world.towns, world.buildings, world.households, world.ancestry_archive, world.societies]:
		for value in values: ids[int(value.id)] = true
	for source in data.voyages:
		if not source is Dictionary or source.get("kind") not in SPEED or source.get("phase") not in ["boarding", "outbound", "returning", "unload"] or source.get("purpose") not in ["explore", "trade", "colony", "migrate"]: return false
		for key in ["id", "home", "progress", "duration", "food", "cargo", "target", "integrity", "wait"]:
			if not WorldState._integer(source.get(key)): return false
		if ids.has(int(source.id)) or source.id <= 0 or source.id >= world.next_id or source.progress < 0 or source.duration < 20 or source.progress >= source.duration or source.food < 0 or source.food > int(HOLD[source.kind]) or source.integrity <= 0 or source.integrity > 12 or source.wait < 0 or source.wait > WorldEconomy.DAY_TICKS: return false
		if source.cargo < 0 or source.cargo > 6 or ((source.cargo == 0) != (source.get("cargo_kind", "") == "")) or source.get("cargo_kind", "") not in ["", "food", "wood"] and not WorldCivilization.GOODS.has(source.get("cargo_kind")): return false


		if not source.get("crew") is Array or source.crew.size() > 3: return false
		for key in ["origin", "landing"]:
			if not valid_point(world, source.get(key)): return false
		if not source.get("route") is Array or source.route.size() < 2 or source.route.size() > 130: return false
		for point in source.route:
			if not valid_point(world, point): return false
		var ship: Dictionary = source.duplicate(true)
		for key in ["id", "home", "progress", "duration", "food", "cargo", "target", "integrity", "wait"]: ship[key] = int(ship[key])
		for key in ["origin", "landing"]:
			for i in 2: ship[key][i] = int(ship[key][i])
		for point in ship.route:
			for i in 2: point[i] = int(point[i])
		for i in ship.crew.size():
			if not WorldState._integer(ship.crew[i]): return false
			ship.crew[i] = int(ship.crew[i])
			var member := WorldLife.person(world, ship.crew[i])
			if member.is_empty() or not WorldLife.adult(world, member) or world.voyage_people.has(member.id) or member.task.get("kind", "") != "travel": return false
			world.voyage_people[member.id] = ship.id
		world.voyages.append(ship)
		world.voyage_index[ship.id] = ship
		ids[ship.id] = true
	for source in data.contacts:
		if not source is Dictionary: return false
		for key in ["a", "b", "tick", "visits", "trust"]:
			if not WorldState._integer(source.get(key)): return false
		if source.a == source.b or source.a <= 0 or source.b <= 0 or source.a >= world.next_id or source.b >= world.next_id or source.tick < 0 or source.tick > world.ticks or source.visits < 1 or source.trust < 0 or source.trust > 100 or not contact(world, source.a, source.b).is_empty(): return false
		var value: Dictionary = source.duplicate()
		for key in value: value[key] = int(value[key])
		world.contacts.append(value)
	for mark in data.explored:
		if not mark is String or not WorldState._integer(data.explored[mark]) or data.explored[mark] < 0 or data.explored[mark] > world.ticks: return false
		world.explored_coasts[mark] = int(data.explored[mark])
	if not data.get("fishing") is Array or data.fishing.size() > 4096: return false
	for row in data.fishing:
		if not row is Array or row.size() != 4: return false
		for value in row:
			if not WorldState._integer(value): return false
		var cell := Vector2i(row[0], row[1])
		if not world.inside(cell) or world.fishing.has(cell) or row[2] < 0 or row[2] > world.ticks / WorldEconomy.DAY_TICKS or row[3] < 0 or row[3] > 6: return false
		world.fishing[cell] = {"day": int(row[2]), "amount": int(row[3])}
	return true

static func valid_point(world, value: Variant) -> bool:
	return value is Array and value.size() == 2 and WorldState._integer(value[0]) and WorldState._integer(value[1]) and world.inside(Vector2i(value[0], value[1]))
