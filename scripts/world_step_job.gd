class_name WorldStepJob
extends RefCounted

enum Phase { CLIMATE, REPAIR, HOMES, NAVIGATION, WORKFORCE, SOCIAL_TICK, CLAIMS, FARMS, PLANS, SPOIL, PEOPLE, TRAVEL, LIFE_REPAIR, FOUND, LIFE_BEGIN, COURT, BIRTHS, SOCIAL, SOCIETY, CIVILIZATION, DAILY_TRAVEL, FINISH }
var world
var phase := Phase.CLIMATE
var cursor := 0
var town_cursor := 0
var residents: Array[Dictionary] = []
var ids: Array[int] = []
var fading := false
var terrain_dirty := false
var finished := false
var units := 0
var navigation_job: WorldNavigationJob
var travel_job: WorldTravelDailyJob
var max_unit_usec := 0
var peak_phase := ""

func _init(value) -> void:
	world = value
	finished = world.regions.failed or world.stepping
	if not finished: world.stepping = true

func advance(budget_usec: int = 4000) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		var before := Time.get_ticks_usec()
		var label := _label()
		var previous_phase := phase
		_unit()
		var elapsed := Time.get_ticks_usec() - before
		if elapsed > max_unit_usec:
			max_unit_usec = elapsed
			peak_phase = Phase.keys()[previous_phase]
		if world.profiling: world.timings[label] = int(world.timings.get(label, 0)) + elapsed
		units += 1
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func _label() -> String:
	if phase == Phase.CLIMATE: return "climate"
	if phase == Phase.REPAIR: return "repair"
	if phase == Phase.HOMES: return "burn"
	if phase >= Phase.WORKFORCE and phase <= Phase.PEOPLE: return "economy"
	if phase == Phase.TRAVEL: return "maritime"
	if phase >= Phase.LIFE_REPAIR and phase <= Phase.BIRTHS: return "life"
	if phase == Phase.SOCIAL: return "social"
	if phase == Phase.SOCIETY: return "society"
	if phase >= Phase.CIVILIZATION and phase <= Phase.DAILY_TRAVEL: return "travel"
	return "other"

func _next() -> void:
	phase += 1
	cursor = 0
	town_cursor = 0
	residents.clear()
	fading = false

func _members() -> bool:
	if town_cursor >= world.towns.size(): return false
	if residents.is_empty(): residents = WorldEconomy.members(world, world.towns[town_cursor]).duplicate()
	return true

func _next_town() -> void:
	town_cursor += 1
	cursor = 0
	residents.clear()
	fading = false

func _unit() -> void:
	match phase:
		Phase.CLIMATE:
			world.population.active = true
			world.population.town_count = -1
			world.population.rebuild(world)
			world.ticks += 1
			WorldClimate.step(world)
			if world.ticks % WorldEconomy.DAY_TICKS == 0 and world.ticks >= world.drought_until: world.regrowth += 1
			_next()
		Phase.REPAIR:
			terrain_dirty = world._step_fire() if not world.fires.is_empty() else false
			world._repair_buildings()
			WorldSociety.invalidate(world)
			_next()
		Phase.HOMES:
			if cursor < world.towns.size():
				var home: Dictionary = world.towns[cursor]
				if world.fires.has(Vector2i(home.x, home.y)):
					var food := mini(1, int(home.food))
					var wood := mini(1, int(home.wood))
					home.food -= food; home.wood -= wood
					world.metrics.lost_food += food; world.metrics.lost_wood += wood
				cursor += 1
			elif cursor < world.towns.size() * 2:
				WorldSociety.ensure_town(world, world.towns[cursor - world.towns.size()])
				cursor += 1
			else: _next()
		Phase.NAVIGATION:
			if navigation_job != null and not navigation_job.finished: navigation_job.unit()
			elif cursor < world.towns.size():
				navigation_job = WorldNavigationJob.new(world, world.towns[cursor]); cursor += 1
			else: navigation_job = null; _next()
		Phase.WORKFORCE:
			world.workforce.begin(world)
			_next()
		Phase.SOCIAL_TICK:
			if cursor < world.people.size():
				WorldSocial.tick_member(world, world.people[cursor]); cursor += 1
			else:
				world.claims.clear()
				_next()
		Phase.CLAIMS:
			if cursor < world.people.size():
				WorldEconomy.step_claim(world, world.people[cursor]); cursor += 1
			else: _next()
		Phase.FARMS:
			if cursor < world.buildings.size():
				WorldEconomy.step_farm(world, world.buildings[cursor]); cursor += 1
			else: _next()
		Phase.PLANS:
			if world.ticks % WorldEconomy.DAY_TICKS == 0 and cursor < world.towns.size():
				WorldEconomy.plan(world, world.towns[cursor]); cursor += 1
			else: _next()
		Phase.SPOIL:
			if world.ticks % (WorldEconomy.DAY_TICKS * 4) == 0 and cursor < world.towns.size():
				WorldEconomy.step_spoil(world, world.towns[cursor]); cursor += 1
			else:
				_next(); cursor = world.people.size() - 1
		Phase.PEOPLE:
			if cursor >= 0:
				WorldEconomy.step_person(world, cursor); cursor -= 1
			else: _next()
		Phase.TRAVEL:
			WorldTravel.step(world)
			WorldMaritime.step(world)
			world.population.ready = false
			world.workforce.plans.clear(); world.workforce.contributions.clear()
			_next()
		Phase.LIFE_REPAIR:
			if world.life_dirty: WorldLife.reconcile(world)
			_next()
		Phase.FOUND:
			if world.ticks % 15 != 0 or cursor >= world.people.size():
				navigation_job = null; _next(); return
			var member: Dictionary = world.people[cursor]
			var cell := Vector2i(member.x, member.y)
			if navigation_job != null:
				if not navigation_job.finished: navigation_job.unit(); return
				world._found_town(member); cursor += 1; navigation_job = null
			elif member.home != -1 or WorldTravel.away(world,member.id) or not WorldLife.adult(world,member) or not world._town_near(cell,28).is_empty() or world.population.nearby(world,cell,143).size()<3:
				cursor += 1
			else: navigation_job = WorldNavigationJob.new(world,{"id":-member.id,"x":cell.x,"y":cell.y})
		Phase.LIFE_BEGIN:
			if world.ticks % WorldEconomy.DAY_TICKS != 0:
				phase = Phase.FINISH
			else:
				WorldLife.reconcile(world)
				_next()
		Phase.COURT:
			if not _members():
				_next()
				for member in world.people: ids.append(int(member.id))
			elif cursor < residents.size():
				WorldLife.court_member(world, world.towns[town_cursor], residents[cursor]); cursor += 1
			else: _next_town()
		Phase.BIRTHS:
			if cursor < ids.size():
				WorldLife.daily_member(world, ids[cursor]); cursor += 1
			else: _next()
		Phase.SOCIAL:
			if not _members(): _next()
			elif cursor < residents.size():
				if fading: WorldSocial.fade_member(world, residents[cursor])
				else: WorldSocial.daily_member(world, world.towns[town_cursor], residents[cursor])
				cursor += 1
			elif not fading and world.ticks % WorldLife.YEAR == 0:
				fading = true; cursor = 0
			else: _next_town()
		Phase.SOCIETY:
			if cursor < world.towns.size():
				WorldSociety.daily_town(world, world.towns[cursor]); cursor += 1
			else: _next()
		Phase.CIVILIZATION:
			if cursor < world.towns.size():
				WorldCivilization.daily_town(world, world.towns[cursor]); cursor += 1
			else: _next()
		Phase.DAILY_TRAVEL:
			if cursor == 0:
				if travel_job == null: travel_job = WorldTravelDailyJob.new(world)
				if not travel_job.finished: travel_job.unit()
				else: cursor = 1
			else:
				WorldMaritime.daily(world)
				_next()
		Phase.FINISH:
			if world.ticks % 300 == 0: world._random_event()
			if terrain_dirty: world.terrain_changed.emit()
			if world.ticks % WorldEconomy.DAY_TICKS == 0: world.regions.trim(world)
			world.workforce.end()
			world.population.active = false
			world.stepping = false
			finished = true
			world.changed.emit()
