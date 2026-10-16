class_name WorldTravel
extends RefCounted

const LIMIT := 32
const MAX_PATH := 2048

static func away(world, id: int) -> bool:
	return world.journey_people.has(id) or WorldMaritime.onboard(world, id)

static func path(world, start: Vector2i, finish: Vector2i) -> Array:
	var job := WorldTravelPathJob.new(world, start, finish)
	job.advance(0)
	return job.result

static func eligible(world, home: Dictionary, group: Array, relocating: bool = false) -> bool:
	if group.is_empty() or group.size()>8: return false
	var adult := false
	var unique := {}
	for id in group:
		var member := WorldLife.person(world,id)
		if unique.has(id) or member.is_empty() or member.home!=home.id or away(world,id) or member.cargo>0 or member.birth_due>=0 or member.health<70 or member.hunger>=35: return false
		if member.task.get("kind","") in ["care","teach","research"] and not relocating: return false
		if member.task.get("kind","")=="care" and not group.has(int(member.task.get("dependent",-1))): return false
		unique[id] = true; adult = adult or WorldLife.adult(world,member)
	return adult

static func launch(world, home: Dictionary, target: Dictionary, group: Array, purpose: String, prepared_path: Variant = null) -> bool:
	if world.journeys.size()>=LIMIT or home.id==target.id or purpose not in ["migrate","trade","aid","colony"] or not eligible(world,home,group,purpose in ["migrate","colony"]): return false
	if purpose=="colony" and group.size()<3: return false
	if purpose=="migrate" and (WorldEconomy.housing(world,target)-WorldEconomy.members(world,target).size()<group.size() or not world.networks.permitted(home.id,target.id,world.ticks)): return false
	var points: Array = path(world,Vector2i(home.x,home.y),Vector2i(target.x,target.y)) if prepared_path==null else prepared_path
	if points.size()<2 or points.size()>MAX_PATH: return false
	var food := ceili((points.size()*(2 if purpose in ["trade","aid"] else 1)+40)*group.size()*0.625/WorldEconomy.NUTRITION)+group.size()*2
	var terms: Dictionary = world.networks.offer(world,home,target) if purpose in ["trade","aid"] else {}
	if purpose in ["trade","aid"] and terms.is_empty(): return false
	var exported_food: int = terms.get("amount",0) if terms.get("kind","")=="food" else 0
	var remaining := maxi(0,WorldEconomy.members(world,home).size()-group.size()) if purpose in ["migrate","colony"] else WorldEconomy.members(world,home).size()*2
	if food>120 or home.food-food-exported_food<remaining: return false
	if purpose=="colony" and home.wood<4: return false
	var journey := {"id":world.next_id,"home":int(home.id),"target":int(target.id),"crew":group.duplicate(),"route":points.duplicate(true),"phase":"boarding","progress":0,"purpose":purpose,"food":food,"cargo":0,"cargo_kind":"","return_kind":"","return_amount":0}
	if not terms.is_empty():
		journey.purpose = "aid" if terms.aid else "trade"
		journey.cargo_kind = terms.kind; journey.cargo = int(terms.amount)
		journey.return_kind = terms.return_kind; journey.return_amount = int(terms.return_amount)
		world.networks.take(world,home,journey.cargo_kind,journey.cargo)
	elif purpose=="colony":
		journey.cargo_kind = "wood"; journey.cargo = mini(6,int(home.wood)); home.wood -= journey.cargo
	if purpose=="colony": world.networks.state_for(world,home).next_migration = world.ticks+WorldLife.YEAR
	world.next_id += 1; home.food -= food
	world.journeys.append(journey); world.journey_index[journey.id] = journey
	for id in group:
		world.journey_people[id] = journey.id
		var member := WorldLife.person(world,id)
		WorldSocial.cancel_lesson(world,member)
		WorldEconomy.set_task(world,member,WorldEconomy.task("travel",Vector2i(home.x,home.y)))
		if WorldLife.adult(world,member): member.job = "merchant" if journey.purpose in ["trade","aid"] else "settler"
	WorldSociety.invalidate(world)
	world.log_event("Караван в пути","%s → %s: %d путешественников, %d еды." % [home.name,target.name,group.size(),food])
	return true

static func member_step(world, member: Dictionary) -> void:
	var journey: Dictionary = world.journey_index.get(world.journey_people.get(member.id, -1), {})
	if journey.is_empty(): return
	if journey.phase == "boarding":
		var home := WorldEconomy.town(world, journey.home)
		if not home.is_empty(): WorldEconomy.move(world, member, Vector2i(home.x, home.y), home)
	if member.hunger >= WorldEconomy.NUTRITION:
		if member.rations > 0: member.rations -= 1
		elif journey.food > 0: journey.food -= 1
		else:
			if member.hunger > 100: world.remove_person(world.people.find(member), "караван остался без еды")
			return
		member.hunger -= WorldEconomy.NUTRITION
		world.metrics.eaten_food += 1
	member.energy = minf(100, member.energy + 0.2)

static func death(world, id: int) -> void:
	var journey: Dictionary = world.journey_index.get(world.journey_people.get(id, -1), {})
	if not journey.is_empty(): journey.crew.erase(id)
	world.journey_people.erase(id)

static func finish(world, journey: Dictionary, home: Dictionary, reconcile_life: bool = true) -> void:
	var relocated: bool=not journey.crew.is_empty()
	for id in journey.crew:
		var member := WorldLife.person(world, id)
		if member.is_empty(): continue
		member.home = int(home.id) if not home.is_empty() else -1
		WorldEconomy.set_task(world, member, {})
		world.journey_people.erase(id)
		world.heritage.returned(world,member)
	journey.crew = []
	if relocated:
		world.population_dirty = true
		world.life_dirty = true
		if reconcile_life: WorldLife.reconcile(world)
		WorldSociety.invalidate(world)
	var amount := 0
	if not home.is_empty():
		amount = mini(journey.food, WorldEconomy.food_capacity(world, home) - int(home.food))
		home.food += amount
		journey.food -= amount
		if journey.cargo > 0:
			var storage: Dictionary = home if journey.cargo_kind in ["food","wood"] else WorldCivilization.ensure(world, home).stock
			var limit: int = WorldEconomy.food_capacity(world, home) if journey.cargo_kind == "food" else (WorldEconomy.wood_capacity(world,home) if journey.cargo_kind=="wood" else WorldCivilization.CAPACITY)
			amount = mini(journey.cargo, limit - int(storage[journey.cargo_kind]))
			storage[journey.cargo_kind] += amount
			journey.cargo -= amount
			if journey.cargo == 0: journey.cargo_kind = ""
		if journey.food > 0 or journey.cargo > 0:
			journey.phase = "unload"
			journey.unload_home = int(home.id)
			return
	else:
		world.metrics.lost_food += int(journey.food) + (int(journey.cargo) if journey.cargo_kind == "food" else 0)
		world.metrics.lost_wood += int(journey.cargo) if journey.cargo_kind=="wood" else 0
		if WorldCivilization.GOODS.has(journey.cargo_kind): world.industry.lost[journey.cargo_kind] += int(journey.cargo)
	world.journey_index.erase(journey.id)
	world.journeys.erase(journey)

static func step(world) -> void:
	for journey in world.journeys.duplicate(): step_journey(world, journey)

static func step_journey(world, journey: Dictionary) -> void:
	if journey.phase == "unload":
		finish(world, journey, WorldEconomy.town(world,int(journey.get("unload_home",journey.target if journey.purpose in ["migrate","colony"] else journey.home))))
		return
	if journey.crew.is_empty():
		finish(world, journey, {})
		return
	if journey.phase == "boarding":
		var ready := true
		for id in journey.crew:
			var member := WorldLife.person(world, id)
			if Vector2i(member.x, member.y) != Vector2i(journey.route[0][0], journey.route[0][1]): ready = false
		if ready: journey.phase = "outbound"
		return
	var direction := -1 if journey.phase == "returning" else 1
	var next: int = int(journey.progress) + direction
	var point := Vector2i(journey.route[next][0], journey.route[next][1])
	if not world.walkable(point) or world.fires.has(point):

		world.networks.failed(world,journey,"Маршрут стал недоступен")
		finish(world,journey,{})
		world.log_event("Путь прерван", "Караван остановился: дорога стала недоступна.")
		return
	journey.progress = next
	for id in journey.crew:
		var member := WorldLife.person(world, id)
		var previous := Vector2i(member.x,member.y)
		member.x = point.x
		member.y = point.y
		world.track_person_move(member,previous)
		world.heritage.visit(world,member,point)
	if journey.phase == "returning" and next == 0:
		finish(world, journey, WorldEconomy.town(world, journey.home))
	elif journey.phase == "outbound" and next == journey.route.size() - 1:
		var home := WorldEconomy.town(world, journey.home)
		var target := WorldEconomy.town(world, journey.target)
		if journey.purpose=="colony" and target.is_empty():
			target = world._town_near(point,28)
			if target.is_empty():
				target = {"id":world.next_id,"name":"Новый очаг %d" % world.next_id,"x":point.x,"y":point.y,"food":0,"wood":0,"level":1}
				world.next_id += 1; world.towns.append(target)
				WorldEconomy.add_building(world,target,"camp",point,true)
				world.heritage.settled(world,target)
				if not home.is_empty(): world.networks.ancestry(world,target,home)
			journey.target = int(target.id)
		if not target.is_empty():
			WorldMaritime.meet(world,home,target,journey.crew,"land")
			if journey.purpose in ["trade","aid"] and not world.networks.exchange(world,journey,home,target,"land"): world.networks.failed(world,journey,"Не удалось выполнить условия обмена")
		if journey.purpose in ["migrate","colony"]:
			if target.is_empty() or (journey.purpose=="migrate" and WorldEconomy.housing(world,target)-WorldEconomy.members(world,target).size()<journey.crew.size()): journey.phase = "returning"; return
			finish(world,journey,target)
			world.log_event("Новый дом","Переселенцы добрались до нового поселения. Родство и навыки сохранены.")
		else: journey.phase = "returning"


static func daily(world) -> void:
	var job := WorldTravelDailyJob.new(world)
	while not job.finished: job.unit()

static func restore(world, source: Variant) -> bool:
	if not source is Array or source.size() > LIMIT: return false
	var ids := {}
	for list in [world.people, world.towns, world.buildings, world.households, world.societies, world.ancestry_archive, world.voyages]:
		for value in list: ids[int(value.id)] = true
	for data in source:
		if not data is Dictionary or data.get("phase") not in ["boarding", "outbound", "returning", "unload"] or data.get("purpose") not in ["trade","aid","migrate","colony"]: return false
		for key in ["id", "home", "target", "progress", "food", "cargo"]:
			if not WorldState._integer(data.get(key)): return false
		if ids.has(int(data.id)) or data.id <= 0 or data.id >= world.next_id or data.food < 0 or data.food > 120 or data.cargo < 0 or data.cargo > 6 or ((data.cargo == 0) != (data.get("cargo_kind", "") == "")): return false
		if data.get("cargo_kind") not in ["","food","wood"] and not WorldCivilization.GOODS.has(data.get("cargo_kind")): return false
		if not data.get("route") is Array or data.route.size() < 2 or data.route.size() > MAX_PATH or data.progress < 0 or data.progress >= data.route.size(): return false
		for i in data.route.size():
			if not WorldMaritime.valid_point(world, data.route[i]): return false
			if i > 0 and Vector2i(data.route[i][0], data.route[i][1]).distance_squared_to(Vector2i(data.route[i-1][0], data.route[i-1][1])) != 1: return false
		if not data.get("crew") is Array or data.crew.size() > 8: return false
		if data.has("unload_home") and (not WorldState._integer(data.unload_home) or data.unload_home<=0 or data.unload_home>=world.next_id): return false
		if not WorldNetworks.valid_terms(data): return false
		var journey: Dictionary = data.duplicate(true)
		journey.return_kind = str(journey.get("return_kind","food" if journey.purpose=="trade" and journey.cargo_kind!="food" else ""))
		journey.return_amount = int(journey.get("return_amount",journey.cargo*2 if journey.return_kind=="food" else 0))
		for key in ["id", "home", "target", "progress", "food", "cargo"]: journey[key] = int(journey[key])
		for point in journey.route:
			for i in 2: point[i] = int(point[i])
		for i in journey.crew.size():
			if not WorldState._integer(journey.crew[i]): return false
			journey.crew[i] = int(journey.crew[i])
			var member := WorldLife.person(world, journey.crew[i])
			if member.is_empty() or away(world, member.id) or member.task.get("kind", "") != "travel": return false
			world.journey_people[member.id] = journey.id
		world.journeys.append(journey)
		world.journey_index[journey.id] = journey
		ids[journey.id] = true
	for member in world.people:
		if member.task.get("kind", "") == "travel" and not away(world, member.id): return false
	return true
