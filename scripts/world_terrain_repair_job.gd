class_name WorldTerrainRepairJob
extends RefCounted

var world
var phase := 0
var cursor := 0
var crew_cursor := 0
var journeys: Array
var repair: WorldBuildingRepairJob
var navigation: WorldNavigationJob
var relocation: WorldNearestLandJob
var removal: WorldPersonRemovalJob
var removal_context: WorldRemovalContext
var life: WorldLifeReconcileJob
var societies: Array
var civilizations: Array
var orphan: Dictionary = {}
var doomed_towns: Dictionary = {}
var finished := false
var workforce_was_active := false

static func needed(value: WorldState, touched: Dictionary) -> bool:
	for home in value.towns:
		var radius := WorldExploration.radius(home)+1
		var area := Rect2i(Vector2i(home.x,home.y)-Vector2i.ONE*radius,Vector2i.ONE*(radius*2+1))
		for key in touched:
			if area.intersects(Rect2i(key*WorldState.CHUNK_SIZE,Vector2i.ONE*WorldState.CHUNK_SIZE)): return true
	if value.population.ready:
		var span := WorldState.CHUNK_SIZE/WorldPopulation.CELL_SIZE
		for key in touched:
			var first: Vector2i = key*span
			for y in span:
				for x in span:
					if not value.population.cells.get(first+Vector2i(x,y),[]).is_empty(): return true
	else:
		for member in value.people:
			if touched.has(WorldState.chunk_of(Vector2i(member.x,member.y))): return true
	for building in value.buildings:
		var area := WorldEconomy.footprint(building)
		for key in touched:
			if area.intersects(Rect2i(key*WorldState.CHUNK_SIZE,Vector2i.ONE*WorldState.CHUNK_SIZE)): return true
	return false

func _init(value) -> void:
	world = value
	workforce_was_active = world.workforce.active
	world.workforce.active = true
	journeys = world.journeys.duplicate()

func unit() -> void:
	if finished: return
	match phase:
		0:
			if cursor < journeys.size():
				var journey: Dictionary = journeys[cursor]
				if crew_cursor < journey.crew.size():
					var member := WorldLife.person(world, journey.crew[crew_cursor]); crew_cursor += 1
					if not member.is_empty() and not world.walkable(Vector2i(member.x, member.y)):
						WorldTravel.finish(world, journey, {}, false)
				else: cursor += 1; crew_cursor = 0
			else: phase = 1; cursor = world.people.size() - 1; removal_context = WorldRemovalContext.new(world)
		1:
			if not removal_context.finished: removal_context.unit(); return
			if removal != null:
				if not removal.finished: removal.unit(); return
				removal = null; relocation = null; cursor -= 1; return
			if relocation != null:
				if not relocation.finished: relocation.unit(); return
				if relocation.result == WorldState.NO_CELL:
					removal = WorldPersonRemovalJob.new(world,world.people[cursor],"потеря земли"); removal.context = removal_context; return
				else:
					world.people[cursor].x = relocation.result.x; world.people[cursor].y = relocation.result.y
				relocation = null; cursor -= 1
			elif cursor >= 0:
				var member: Dictionary = world.people[cursor]
				if WorldTravel.away(world, member.id):
					if WorldEconomy.town(world, member.home).is_empty(): member.home = -1
				elif not world.walkable(Vector2i(member.x, member.y)):
					relocation = WorldNearestLandJob.new(world,Vector2i(member.x,member.y)); return
				cursor -= 1
			else: phase = 10; cursor = 0
		10:
			if cursor >= world.towns.size():
				if doomed_towns.is_empty(): phase = 2; cursor = world.towns.size()-1
				else: phase = 11; cursor = 0
				return
			var home: Dictionary = world.towns[cursor]; cursor += 1
			if not world.walkable(Vector2i(home.x,home.y)): doomed_towns[home.id] = true
		11:
			if cursor >= world.buildings.size(): phase = 2; cursor = world.towns.size()-1; return
			var value: Dictionary = world.buildings[cursor]; cursor += 1
			if doomed_towns.has(value.town): world.heritage.remember_building(world,value)
		2:
			if cursor >= 0:
				var home: Dictionary = world.towns[cursor]
				if not world.walkable(Vector2i(home.x, home.y)):
					world.heritage.abandon(world,home,"Потеря земли")
					world.heritage.forget_origin(home)
					world.log_event("Поселение исчезло", "%s потеряло землю под собой." % home.name)
					world.metrics.lost_food += home.food; world.metrics.lost_wood += home.wood
					WorldExploration.forget(world, home)
					world.networks.forget_home(home.id)
					world.towns.remove_at(cursor)
				cursor -= 1
			else: phase = 3
		3:
			if repair == null: repair = WorldBuildingRepairJob.new(world)
			if not repair.finished: repair.unit()
			else: world.population_dirty = true; phase = 4; cursor = 0
		4:
			if navigation != null:
				if not navigation.finished: navigation.unit()
				else: navigation = null
			elif cursor < world.towns.size():
				navigation = WorldNavigationJob.new(world, world.towns[cursor]); cursor += 1
			else: phase = 5; cursor = 0
		5:
			if cursor < world.people.size():
				var member: Dictionary = world.people[cursor]; cursor += 1
				if WorldTravel.away(world, member.id):
					if WorldEconomy.town(world, member.home).is_empty(): member.home = -1
					return
				var home := WorldEconomy.town(world, member.home)
				if home.is_empty() or not world.navigation[home.id].parents.has(Vector2i(member.x, member.y)):
					member.home = -1; WorldEconomy.set_task(world, member, {}); return
				if member.task.is_empty(): return
				var target := Vector2i(member.task.x, member.task.y)
				var invalid: bool = not world.walkable(target) or not world.navigation[home.id].parents.has(target)
				if member.task.kind in ["supply", "build", "plant", "harvest"] and WorldEconomy.building(world, member.task.building).is_empty(): invalid = true
				if member.task.kind in ["gather_food", "gather_wood"] and not world.building_at(target).is_empty(): invalid = true
				if member.task.kind == "gather_wood" and world.wood_at(target) == 0: invalid = true
				if invalid: WorldEconomy.set_task(world, member, {})
			else: life = WorldLifeReconcileJob.new(world); phase = 6
		6:
			if not life.finished: life.unit()
			else: societies = world.societies.duplicate(); cursor = societies.size() - 1; phase = 7
		7:
			if not orphan.is_empty():
				if crew_cursor < world.people.size():
					var member: Dictionary = world.people[crew_cursor]; crew_cursor += 1
					if member.task.get("society", -1) == orphan.id: WorldEconomy.set_task(world, member, {})
				else:
					world.society_index.erase(orphan.town); world.societies.erase(orphan); orphan = {}
			elif cursor >= 0:
				var society: Dictionary = societies[cursor]; cursor -= 1
				if WorldEconomy.town(world, society.town).is_empty(): orphan = society; crew_cursor = 0
			else:
				WorldSociety.invalidate(world); civilizations = world.civilization.keys(); cursor = 0; phase = 8
		8:
			if cursor < civilizations.size():
				var id: int = civilizations[cursor]; cursor += 1
				if WorldEconomy.town(world, id).is_empty():
					for key in WorldCivilization.GOODS: world.industry.lost[key] += int(world.civilization[id].stock[key])
					world.civilization.erase(id)
			else: phase = 9; cursor = 0
		9:
			if cursor < world.towns.size(): WorldCivilization.ensure(world, world.towns[cursor]); cursor += 1
			else:
				if not workforce_was_active: world.workforce.end()
				finished = true
