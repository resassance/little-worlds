class_name WorldWorkforce
extends RefCounted

const GROUP_SIZE := 32
var active := false
var plans: Dictionary = {}
var building_lists: Dictionary = {}
var building_counts: Dictionary = {}
var contributions: Dictionary = {}
var plan_builds := 0
var building_count := -1
var shipments: Dictionary = {}
var shipment_scans := 0

func begin(world, refresh_buildings: bool = true) -> void:
	active = true
	plans.clear(); contributions.clear(); shipments.clear()
	shipment_scans = 0
	if not refresh_buildings and building_count == world.buildings.size(): return
	building_count = world.buildings.size()
	building_lists.clear(); building_counts.clear()
	plan_builds = 0
	for value in world.buildings:
		if not building_lists.has(value.town): building_lists[value.town] = []
		building_lists[value.town].append(value)
		_count_building(value, 1)

func end() -> void:
	active = false

func buildings(world, home: Dictionary) -> Array:
	if active: return building_lists.get(home.id, [])
	var result: Array = []
	for value in world.buildings:
		if value.town == home.id: result.append(value)
	return result

func building_added(value: Dictionary) -> void:
	if not active: building_count = -1; return
	building_count += 1
	if not building_lists.has(value.town): building_lists[value.town] = []
	building_lists[value.town].append(value)
	_count_building(value, 1)

func _count_building(value: Dictionary, amount: int) -> void:
	if not building_counts.has(value.town): building_counts[value.town] = {}
	var counts: Dictionary = building_counts[value.town]
	if not counts.has(value.kind): counts[value.kind] = [0, 0]
	counts[value.kind][0] += amount
	if value.ready: counts[value.kind][1] += amount

func building_removed(value: Dictionary) -> void:
	if building_lists.has(value.town):
		building_lists[value.town].erase(value)
		_count_building(value, -1)
	building_count -= 1

func building_ready(value: Dictionary) -> void:
	if building_counts.has(value.town) and building_counts[value.town].has(value.kind): building_counts[value.town][value.kind][1] += 1

func count(home: Dictionary, kind: String, ready_only: bool) -> int:
	var counts: Dictionary = building_counts.get(home.id, {})
	return int(counts.get(kind, [0, 0])[1 if ready_only else 0])

static func role(member: Dictionary) -> String:
	var kind: String = member.task.get("kind", "")
	if kind in ["gather_food", "fish"] or (kind == "deliver" and member.cargo_kind == "food"): return "food"
	if kind in ["plant", "harvest"]: return "farm"
	if kind == "gather_wood" or (kind == "deliver" and member.cargo_kind == "wood"): return "wood"
	if kind in ["build", "supply", "supply_goods", "terraform"]: return "build"
	if kind in ["quarry", "manufacture"]: return "industry"
	return ""

static func base_need(world, member: Dictionary) -> float:
	var age: int = WorldLife.years(world, member)
	return (0.25 if age < 13 else (0.375 if age < 18 else 0.5)) * WorldEconomy.DAY_TICKS / WorldEconomy.NUTRITION

static func cold(world, cell: Vector2i) -> bool:
	return WorldClimate.biome(world, cell) >= 4 or (world.climate.seasons and WorldClimate.season(world) == 3)

func context(world, home: Dictionary) -> Dictionary:

	if not active or world.population_dirty:
		plans.clear(); contributions.clear(); shipments.clear()
	if plans.has(home.id): return plans[home.id]
	var residents: Array[Dictionary] = WorldEconomy.members(world, home)
	var result := {"population": 0, "food_workers": 0, "wood_workers": 0, "warm_need": 0.0, "cold_need": 0.0, "teams": {}, "available": {}, "resources": {}}
	var uniform: bool = world.climate.mode == "uniform" and world.biome_overrides.is_empty()
	var uniform_cold: bool = uniform and (int(world.climate.biome) >= 4 or (world.climate.seasons and WorldClimate.season(world) == 3))
	plans[home.id] = result
	plan_builds += 1
	for member in residents:
		if WorldLife.adult(world, member): result.population += 1
		var need := base_need(world, member)
		result["cold_need" if (uniform_cold if uniform else cold(world, Vector2i(member.x, member.y))) else "warm_need"] += need
		add_contribution(result, member)
		contributions[member.id] = {"home": int(home.id), "role": role(member)}
	return result

static func add_contribution(plan: Dictionary, member: Dictionary) -> void:
	var job := role(member)
	if job in ["food", "farm"]: plan.food_workers += 1
	if job == "wood": plan.wood_workers += 1
	if job.is_empty(): return
	if not plan.teams.has(job): plan.teams[job] = {}
	plan.teams[job][member.id] = true

func task_changed(world, member: Dictionary) -> void:
	if not active: return
	var previous: Dictionary = contributions.get(member.id, {})
	if not previous.is_empty() and plans.has(previous.home):
		var plan: Dictionary = plans[previous.home]
		if previous.role in ["food", "farm"]: plan.food_workers -= 1
		if previous.role == "wood": plan.wood_workers -= 1
		if plan.teams.has(previous.role): plan.teams[previous.role].erase(member.id)
	if plans.has(member.home):
		var plan: Dictionary = plans[member.home]
		add_contribution(plan, member)
		for skill in plan.available: update_rank(world, plan.available[skill], member, skill)
	contributions[member.id] = {"home": int(member.home), "role": role(member)}

func rehomed(world, member: Dictionary, previous: int) -> void:
	shipments.erase(previous); shipments.erase(member.home)
	if not active: plans.clear(); contributions.clear(); return
	var adult: bool = WorldLife.adult(world, member)
	var field := "cold_need" if cold(world, Vector2i(member.x, member.y)) else "warm_need"
	var need := base_need(world, member)
	var job := role(member)
	if plans.has(previous):
		var plan: Dictionary = plans[previous]
		if adult: plan.population -= 1
		plan[field] -= need
		if job in ["food", "farm"]: plan.food_workers -= 1
		if job == "wood": plan.wood_workers -= 1
		if plan.teams.has(job): plan.teams[job].erase(member.id)
		for skill in plan.available: plan.available[skill].erase(int(member.id))
	if plans.has(member.home):
		var plan: Dictionary = plans[member.home]
		if adult: plan.population += 1
		plan[field] += need
		add_contribution(plan, member)
		for skill in plan.available: update_rank(world, plan.available[skill], member, skill)
	contributions[member.id] = {"home": int(member.home), "role": job}

func daily_need(world, home: Dictionary) -> float:
	var plan := context(world, home)
	if float(plan.cold_need) == 0: return float(plan.warm_need)
	var data: Dictionary = WorldCivilization.get_data(world, home.id)
	var multiplier := 1.05 if not data.is_empty() and data.stock.cloth > 0 else 1.25
	return float(plan.warm_need) + float(plan.cold_need) * multiplier

func food_days(world, home: Dictionary) -> float:
	var plan := context(world,home)
	var need := float(plan.warm_need)
	if float(plan.cold_need) > 0:
		var data: Dictionary = WorldCivilization.get_data(world,home.id)
		need += float(plan.cold_need)*(1.05 if not data.is_empty() and data.stock.cloth > 0 else 1.25)
	return float(home.food)/maxf(0.25,need)

func resource(world, member: Dictionary, home: Dictionary, kind: String) -> Vector2i:
	var plan := context(world, home)
	if not plan.resources.has(kind): plan.resources[kind] = {"cursor": 0, "offers": []}
	var pool: Dictionary = plan.resources[kind]
	var candidates: Array[Vector2i] = WorldEconomy.navigation(world, home)[kind]


	while true:
		if pool.offers.size() < 16:
			while pool.offers.size() < GROUP_SIZE and pool.cursor < candidates.size():
				var cell := candidates[pool.cursor]
				pool.cursor += 1
				var offer := {"cell": cell, "key": "%s:%d:%d" % ["gather_food" if kind == "food" else "gather_wood", cell.x, cell.y]}
				if available_resource(world, offer, kind): pool.offers.append(offer)
		var best := -1
		var distance := INF
		var position := Vector2i(member.x, member.y)
		var checked := 0
		var i := 0
		while i < pool.offers.size() and checked < 16:
			var offer: Dictionary = pool.offers[i]
			if world.claims.has(offer.key) or world.fires.has(offer.cell) or world.occupied.has(offer.cell):
				pool.offers.remove_at(i); continue
			var current := position.distance_squared_to(offer.cell)
			if current < distance: distance = current; best = i
			i += 1; checked += 1
		if best == -1:
			if pool.cursor < candidates.size(): continue
			return WorldState.NO_CELL
		var selected: Dictionary = pool.offers[best]
		pool.offers.remove_at(best)
		if available_resource(world, selected, kind): return selected.cell
	return WorldState.NO_CELL

static func available_resource(world, offer: Dictionary, kind: String) -> bool:
	var cell: Vector2i = offer.cell
	if world.claims.has(offer.key) or world.fires.has(cell) or world.occupied.has(cell): return false
	return world.food_at(cell) > 0 if kind == "food" else world.wood_at(cell) > 0

func has_resource(world, home: Dictionary, kind: String) -> bool:
	var plan := context(world, home)
	if not plan.has("availability"): plan.availability = {}
	if plan.availability.has(kind): return plan.availability[kind]
	var available := false
	for cell in WorldEconomy.navigation(world, home)[kind]:
		if world.fires.has(cell) or world.occupied.has(cell): continue
		if (world.food_at(cell) if kind == "food" else world.wood_at(cell)) > 0:
			available = true
			break
	plan.availability[kind] = available
	return available

func fishing_coast(world, home: Dictionary, limit: int) -> Dictionary:
	var plan := context(world, home)
	var key := "fishing:%d" % limit
	if not plan.resources.has(key): plan.resources[key] = {"cursor": 0}
	var pool: Dictionary = plan.resources[key]
	var coasts: Array = WorldEconomy.navigation(world, home).coasts
	while pool.cursor < coasts.size():
		var coast: Dictionary = coasts[pool.cursor]
		pool.cursor += 1
		var point: Vector2i = coast.land
		if world.fires.has(point) or world.claims.has("fish:%d:%d" % [point.x, point.y]): continue
		var used: Dictionary = world.fishing.get(coast.water, {})
		if used.get("day", -1) == world.ticks / WorldEconomy.DAY_TICKS and used.get("amount", 0) >= limit: continue
		return coast
	return {}

func moved(world, member: Dictionary, previous: Vector2i) -> void:
	if not active or not plans.has(member.home): return
	if world.climate.mode == "uniform" and world.climate.biome < 4 and not world.climate.seasons and world.biome_overrides.is_empty(): return
	var was_cold := cold(world, previous)
	if was_cold == cold(world, Vector2i(member.x, member.y)): return
	var plan: Dictionary = plans[member.home]
	var amount := base_need(world, member)
	plan.cold_need += -amount if was_cold else amount
	plan.warm_need += amount if was_cold else -amount

static func score(member: Dictionary, skill: String) -> int:
	return int(member.skills[skill]) * 4 + int(member.traits.diligence) + WorldVocation.score(member, skill)

static func before(world, a: int, b: int, skill: String) -> bool:
	var left: Dictionary = world.person_index[a]
	var right: Dictionary = world.person_index[b]
	var left_score := score(left,skill)
	var right_score := score(right,skill)
	return left_score > right_score or (left_score == right_score and a < b)

static func update_rank(world, ids: Array, member: Dictionary, skill: String) -> void:
	ids.erase(int(member.id))
	if not member.task.is_empty() or member.cargo > 0 or not WorldLife.adult(world, member): return
	var first := 0
	var last := ids.size()
	var own_score := score(member,skill)
	while first < last:
		var mid := (first + last) / 2
		var other_score := score(world.person_index[ids[mid]],skill)
		if other_score > own_score or (other_score == own_score and int(ids[mid]) < int(member.id)): first = mid + 1
		else: last = mid
	ids.insert(first, int(member.id))

func skill_changed(world, member: Dictionary, skill: String) -> void:
	if not active or not plans.has(member.home): return
	var plan: Dictionary = plans[member.home]
	if plan.available.has(skill): update_rank(world, plan.available[skill], member, skill)

func preferred(world, member: Dictionary, home: Dictionary, skill: String) -> bool:
	var plan := context(world, home)
	if not plan.available.has(skill):
		var ids: Array = []
		var scores := {}
		for other in WorldEconomy.members(world, home):
			if WorldLife.adult(world, other) and other.task.is_empty() and other.cargo == 0:
				ids.append(int(other.id)); scores[other.id] = score(other,skill)
		ids.sort_custom(func(a: int, b: int): return scores[a] > scores[b] or (scores[a] == scores[b] and a < b))
		plan.available[skill] = ids
	for id in plan.available[skill]:
		var other: Dictionary = world.person_index.get(id, {})
		if other.is_empty() or other.id == member.id or other.home != member.home or not other.task.is_empty() or other.cargo > 0 or other.hunger >= 35 or other.energy < 18 or other.birth_due >= 0: continue
		if not WorldLife.care_candidate(world, other).is_empty(): continue
		return score(member, skill) > score(other, skill) or (score(member, skill) == score(other, skill) and member.id < other.id)
	return true

func group_count(world, home: Dictionary) -> int:
	var plan := context(world, home)
	var total := 0
	for team in plan.teams.values(): total += ceili(team.size() / float(GROUP_SIZE))
	return total

func in_transit(world, home: Dictionary, building: int, kind: String, goods: bool = false) -> int:
	if world.population_dirty: shipments.clear()
	if not shipments.has(home.id):
		var totals := {}
		for member in WorldEconomy.members(world, home):
			var task_kind: String = member.task.get("kind", "")
			if member.cargo <= 0 or task_kind not in ["supply", "supply_goods"]: continue
			var id: int = int(member.task.building)
			if not totals.has(id): totals[id] = {"wood": 0, "goods": {}}
			if task_kind == "supply" and member.cargo_kind == "wood": totals[id].wood += int(member.cargo)
			elif task_kind == "supply_goods": totals[id].goods[member.cargo_kind] = int(totals[id].goods.get(member.cargo_kind, 0)) + int(member.cargo)
		shipments[home.id] = totals
		shipment_scans += 1
	var delivery: Dictionary = shipments[home.id].get(building, {})
	return int(delivery.get("goods", {}).get(kind, 0)) if goods else int(delivery.get("wood", 0))
