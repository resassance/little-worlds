class_name WorldMaritimeDailyJob
extends RefCounted

var world
var phase := 0
var cursor := 0
var home_cursor := 0
var homes: Array
var home: Dictionary = {}
var vessel: Dictionary = {}
var destinations: Array[Dictionary] = []
var fishing: Array
var keys: Array = []
var buildings: Array = []
var navigation_job: WorldNavigationJob
var candidate: Dictionary = {}
var route_job: WorldSeaRouteJob
var finished := false

func _init(value) -> void:
	world = value
	fishing = world.fishing.keys()
	homes = world.towns.duplicate()

func _next_home() -> void:
	home_cursor += 1; cursor = 0; phase = 1
	destinations.clear(); vessel = {}; navigation_job = null; route_job = null

func _offer(coast: Dictionary) -> void:
	if coast.is_empty(): return
	coast.priority = WorldMaritime.destination_priority(world, home, coast)
	coast.distance = coast.land.distance_squared_to(Vector2i(home.x, home.y))
	var first := 0
	var last := destinations.size()
	while first < last:
		var mid := (first + last) / 2
		var other: Dictionary = destinations[mid]
		if other.priority < coast.priority or (other.priority == coast.priority and other.distance <= coast.distance): first = mid + 1
		else: last = mid
	destinations.insert(first, coast)

func unit() -> void:
	if finished: return
	match phase:
		0:
			if cursor < fishing.size():
				var cell: Vector2i = fishing[cursor]; cursor += 1
				if world.fishing[cell].day < world.ticks / WorldEconomy.DAY_TICKS - 1: world.fishing.erase(cell)
			else:
				if world.ticks % (WorldEconomy.DAY_TICKS * 3) != 0: finished = true; return
				phase = 1; cursor = 0
		1:
			if home_cursor >= homes.size(): finished = true; return
			home = homes[home_cursor]
			for ship in world.voyages:
				if ship.home == home.id: _next_home(); return
			if WorldEconomy.food_days(world, home) < 10: _next_home(); return
			buildings = world.workforce.buildings(world, home).duplicate()
			phase = 2; cursor = 0
		2:
			if cursor >= buildings.size(): _next_home(); return
			var value: Dictionary = buildings[cursor]; cursor += 1
			if value.town != home.id or value.kind not in ["boat", "sailboat"] or not value.ready: return
			vessel = value
			phase = 3; cursor = 0
		3:
			if navigation_job != null:
				if not navigation_job.finished: navigation_job.unit(); return
				var coast := WorldMaritime.shore(world, candidate, Vector2i(home.x, home.y))
				if not coast.is_empty(): coast.town = int(candidate.id)
				_offer(coast); navigation_job = null
			elif cursor < world.towns.size():
				candidate = world.towns[cursor]; cursor += 1
				if candidate.id != home.id: navigation_job = WorldNavigationJob.new(world, candidate)
			else: keys = world.region_keys(); cursor = 0; phase = 4
		4:
			if navigation_job != null:
				if not navigation_job.finished: navigation_job.unit(); return
				var coast := WorldMaritime.shore(world, candidate, Vector2i(home.x, home.y))
				world.navigation.erase(candidate.id)
				var resident: Dictionary = world._town_near(Vector2i(candidate.x, candidate.y), 28)
				if not resident.is_empty() and not coast.is_empty(): coast.town = int(resident.id)
				_offer(coast); navigation_job = null
			elif cursor < keys.size():
				var key: Vector2i = keys[cursor]; cursor += 1
				if key == WorldState.chunk_of(Vector2i(home.x, home.y)): return
				var land: Vector2i = world.nearest_land(key * WorldState.CHUNK_SIZE + Vector2i(16, 16), 16)
				if land == WorldState.NO_CELL or WorldEconomy.navigation(world, home).parents.has(land): return
				candidate = {"id": -vessel.id - 1, "x": land.x, "y": land.y}
				navigation_job = WorldNavigationJob.new(world, candidate)
			else: phase = 5; cursor = 0
		5:
			if cursor >= destinations.size(): _next_home(); return
			var destination: Dictionary = destinations[cursor]
			var known: bool = not WorldMaritime.contact(world, home.id, destination.get("town", -1)).is_empty()
			var mark := "%d:%d:%d" % [home.id, destination.land.x, destination.land.y]
			if not known and world.explored_coasts.has(mark): cursor += 1; return
			var departure := WorldMaritime.shore(world, home, destination.land)
			if departure.is_empty(): cursor += 1; return
			route_job = WorldSeaRouteJob.new(world, departure.water, destination.water)
			phase = 6
		6:
			if not route_job.finished: route_job.unit(); return
			var destination: Dictionary = destinations[cursor]
			var known: bool = not WorldMaritime.contact(world, home.id, destination.get("town", -1)).is_empty()
			var purpose := "trade" if known else "explore"
			if not known and destination.get("town", -1) == -1 and WorldEconomy.members(world, home).size() >= 12: purpose = "colony"
			if known and WorldEconomy.food_days(world, home) < 12 and WorldEconomy.housing(world, WorldEconomy.town(world, destination.town)) > WorldEconomy.members(world, WorldEconomy.town(world, destination.town)).size() + 1: purpose = "migrate"
			if WorldMaritime.launch(world, home, vessel, destination, purpose, route_job.result): _next_home()
			else: cursor += 1; phase = 5; route_job = null
