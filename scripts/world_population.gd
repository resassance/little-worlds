class_name WorldPopulation
extends RefCounted

const CELL_SIZE := 8
var active := false
var ready := false
var cells: Dictionary = {}
var locations: Dictionary = {}
var order: Dictionary = {}
var dependents: Dictionary = {}
var town_index: Dictionary = {}
var town_count := -1
var monotonic_ids := true
var settling := false
var shelter_load: Dictionary = {}

func clear() -> void:
	active = false
	ready = false
	cells.clear(); locations.clear(); order.clear(); dependents.clear()
	town_index.clear(); town_count = -1
	settling = false; shelter_load.clear()

static func bucket(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CELL_SIZE), floori(float(cell.y) / CELL_SIZE))

func rebuild(world) -> void:
	var job := WorldPopulationRebuildJob.new(world)
	while not job.finished: job.unit()

func moved(world, member: Dictionary) -> void:
	if not ready: return
	var key := bucket(Vector2i(member.x, member.y))
	var previous: Vector2i = locations.get(member.id, key)
	if previous == key: return
	if cells.has(previous):
		cells[previous].erase(int(member.id))
		if cells[previous].is_empty(): cells.erase(previous)
	if not cells.has(key): cells[key] = []
	var ids: Array = cells[key]
	var first := 0
	var last := ids.size()
	while first < last:
		var mid := (first + last) / 2
		if int(order[ids[mid]]) < int(order[member.id]): first = mid + 1
		else: last = mid
	ids.insert(first, int(member.id)); locations[member.id] = key

func nearby(world, center: Vector2i, radius_squared: int, home: Variant = null, options: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var limit: int = int(options.get("limit", 0))
	if not active and not ready:
		for member in world.people:
			if home != null and member.home != home: continue
			if not accepts(world, member, options): continue
			if center.distance_squared_to(Vector2i(member.x, member.y)) <= radius_squared:
				result.append(member)
				if limit > 0 and result.size() >= limit: break
		return result
	if not ready: rebuild(world)
	var radius := ceili(sqrt(float(radius_squared)))
	var first := bucket(center - Vector2i.ONE * radius)
	var last := bucket(center + Vector2i.ONE * radius)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var ids: Array = cells.get(Vector2i(x, y), [])
			var start := 0
			var end := ids.size()
			var after: int = int(options.get("after_id", -1))
			if limit > 0 and after >= 0 and monotonic_ids:
				while start < end:
					var mid := (start + end) / 2
					if int(ids[mid]) <= after: start = mid + 1
					else: end = mid
			var accepted := 0
			for i in range(start, ids.size()):
				var id: int = int(ids[i])
				var member: Dictionary = world.person_index.get(id, {})
				if member.is_empty() or (home != null and member.home != home): continue
				if not accepts(world, member, options) or center.distance_squared_to(Vector2i(member.x, member.y)) > radius_squared: continue
				if limit == 0: result.append(member); continue
				var position := result.size()
				while position > 0 and int(order[result[position - 1].id]) > int(order[id]): position -= 1
				if position < limit:
					result.insert(position, member)
					if result.size() > limit: result.pop_back()
				accepted += 1
				if accepted >= limit: break
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(order[a.id]) < int(order[b.id]))
	return result

static func accepts(world, member: Dictionary, options: Dictionary) -> bool:
	if options.is_empty(): return true
	if member.id == options.get("exclude_id", -1) or member.id <= options.get("after_id", -1): return false
	if options.get("courtship", false):
		if member.sex == options.sex or member.partner != -1 or member.courting != -1 or member.hunger > 40 or not WorldLife.adult(world, member): return false
	return not options.get("local", false) or not WorldTravel.away(world, member.id)

func children(world, guardian: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not active and not ready:
		for member in world.people:
			if member.guardian == guardian.id and member.home == guardian.home: result.append(member)
		return result
	if not ready: rebuild(world)
	for id in dependents.get(guardian.id, []):
		var member: Dictionary = world.person_index.get(id, {})
		if not member.is_empty() and member.guardian == guardian.id and member.home == guardian.home: result.append(member)
	return result

func town(world, id: int) -> Dictionary:
	if id < 0: return {}
	if not active:
		for value in world.towns:
			if value.id == id: return value
		return {}
	if town_count != world.towns.size() or not town_index.has(id):
		town_index.clear()
		for value in world.towns: town_index[value.id] = value
		town_count = world.towns.size()
	return town_index.get(id, {})

func begin_settlement(world) -> void:
	shelter_load.clear()
	for family in world.households:
		if family.dwelling != -1: shelter_load[family.dwelling] = int(shelter_load.get(family.dwelling, 0)) + family.members.size()
	settling = true

func end_settlement() -> void:
	settling = false; shelter_load.clear()

func dwelling_changed(family: Dictionary, id: int) -> void:
	if settling:
		if family.dwelling != -1: shelter_load[family.dwelling] = int(shelter_load.get(family.dwelling, 0)) - family.members.size()
		if id != -1: shelter_load[id] = int(shelter_load.get(id, 0)) + family.members.size()
	family.dwelling = id
