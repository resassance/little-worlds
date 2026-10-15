class_name WorldStepJob
extends RefCounted

enum Phase { CLIMATE, WEATHER, REPAIR, HOMES, NAVIGATION, WORKFORCE, SOCIAL_TICK, CLAIMS, FARMS, PLANS, SPOIL, PEOPLE, TRAVEL, LIFE_REPAIR, FOUND, LIFE_BEGIN, COURT, BIRTHS, SOCIAL, SOCIETY, CIVILIZATION, DAILY_TRAVEL, LANDSCAPE, FINISH }
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
var population_job: WorldPopulationRebuildJob
var climate_job: WorldClimateStepJob
var weather_job: WorldWeatherStepJob
var heritage_job: WorldHeritageJob
var repair_job: WorldBuildingRepairJob
var life_job: WorldLifeReconcileJob
var sea_daily_job: WorldMaritimeDailyJob
var sea_step_job: WorldMaritimeStepJob
var fire_job: WorldFireStepJob
var journeys: Array = []
var construction_job: WorldConstructionPlanJob
var removal_context: WorldRemovalContext
var landscape_job: WorldLandscapeJob

func _init(value) -> void:
	world = value
	finished = world.regions.failed or world.stepping
	if not finished: world.stepping = true

func advance(budget_usec: int = 4000) -> bool:
	if budget_usec == 0 and not world.profiling:
		while not finished: _unit(); units += 1
		return finished
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		var before := Time.get_ticks_usec()
		var label := _label() if world.profiling else ""
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
	if phase == Phase.WEATHER: return "weather"
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
	if not world.person_removals.is_empty():
		if removal_context == null: removal_context = WorldRemovalContext.new(world)
		if not removal_context.finished: removal_context.unit(); return
		var job: WorldPersonRemovalJob = world.person_removals[0]
		job.context = removal_context
		job.unit()
		if job.finished: world.removal_ids.erase(job.member.id); world.person_removals.pop_front()
		return
	removal_context = null
	match phase:
		Phase.CLIMATE:
			if cursor == 0:
				world.population.active = true
				world.population.town_count = -1
				population_job = null if world.population.ready else WorldPopulationRebuildJob.new(world); cursor = 1
			elif cursor == 1:
				if population_job != null and not population_job.finished: population_job.unit(); return
				world.ticks += 1
				climate_job = WorldClimateStepJob.new(world); cursor = 2
			else:
				if not climate_job.finished: climate_job.unit(); return
				if world.ticks % WorldEconomy.DAY_TICKS == 0 and world.ticks >= world.drought_until: world.regrowth += 1
				_next()
		Phase.WEATHER:
			if weather_job == null: weather_job = WorldWeatherStepJob.new(world)
			if not weather_job.finished: weather_job.unit(); return
			_next()
		Phase.REPAIR:
			if heritage_job == null: heritage_job = WorldHeritageJob.new(world)
			if not heritage_job.finished: heritage_job.unit(); return
			if fire_job == null: fire_job = WorldFireStepJob.new(world)
			if not fire_job.finished: fire_job.unit(); return
			terrain_dirty = fire_job.dirty
			if repair_job == null: repair_job = WorldBuildingRepairJob.new(world)
			if not repair_job.finished: repair_job.unit(); return
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
			if navigation_job != null:
				if not navigation_job.finished: navigation_job.unit()
				else:
					WorldExploration.report(world, navigation_job.home)
					navigation_job = null
			elif cursor < world.towns.size():
				var home: Dictionary = world.towns[cursor]
				WorldExploration.prepare(world, home)
				navigation_job = WorldNavigationJob.new(world, home); cursor += 1
			else: navigation_job = null; _next()
		Phase.WORKFORCE:
			world.workforce.begin(world, false)
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
				if construction_job == null: construction_job = WorldConstructionPlanJob.new(world, world.towns[cursor])
				if not construction_job.finished: construction_job.unit()
				else: construction_job = null; cursor += 1
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
			if cursor == 0: journeys = world.journeys.duplicate(); cursor = 1
			elif cursor <= journeys.size(): WorldTravel.step_journey(world, journeys[cursor - 1]); cursor += 1
			else:
				if sea_step_job == null: sea_step_job = WorldMaritimeStepJob.new(world)
				if not sea_step_job.finished: sea_step_job.unit(); return
				if not journeys.is_empty() or not sea_step_job.ships.is_empty(): world.population.ready = false
				population_job = null
				world.workforce.plans.clear(); world.workforce.contributions.clear()
				_next()
		Phase.LIFE_REPAIR:
			if life_job == null and world.life_dirty: life_job = WorldLifeReconcileJob.new(world)
			if life_job != null and not life_job.finished: life_job.unit(); return
			if world.population.ready: life_job = null; population_job = null; _next(); return
			if population_job == null: population_job = WorldPopulationRebuildJob.new(world); return
			population_job.unit()
			if population_job.finished: life_job = null; population_job = null; _next()
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
				phase = Phase.LANDSCAPE; cursor = 0
			else:
				if life_job == null: life_job = WorldLifeReconcileJob.new(world)
				if not life_job.finished: life_job.unit(); return
				if population_job == null: population_job = WorldPopulationRebuildJob.new(world); return
				population_job.unit()
				if population_job.finished: life_job = null; population_job = null; _next()
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
				if sea_daily_job == null: sea_daily_job = WorldMaritimeDailyJob.new(world)
				if not sea_daily_job.finished: sea_daily_job.unit()
				else: _next()
		Phase.LANDSCAPE:
			if landscape_job == null: landscape_job = WorldLandscapeJob.new(world)
			if not landscape_job.finished: landscape_job.unit(); return
			_next()
		Phase.FINISH:
			if cursor == 0:
				population_job = null if world.population.ready else WorldPopulationRebuildJob.new(world); cursor = 1
			if population_job != null and not population_job.finished: population_job.unit(); return
			if not world.navigation_cleanup.is_empty(): world.reclaim_navigation(300); return
			if terrain_dirty: world.terrain_changed.emit()
			if world.ticks % WorldEconomy.DAY_TICKS == 0: world.regions.trim(world, WorldState.NO_CELL, 1)
			world.workforce.end()
			world.population.active = false
			world.stepping = false
			finished = true
			world.changed.emit()
