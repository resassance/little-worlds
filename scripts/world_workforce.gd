class_name WorldWorkforce
extends RefCounted

const GROUP_SIZE := 32
var active := false
var plans: Dictionary = {}
var building_lists: Dictionary = {}
var contributions: Dictionary = {}
var plan_builds := 0

func begin(world) -> void:
	active = true
	plans.clear(); building_lists.clear(); contributions.clear()
	plan_builds = 0
	for value in world.buildings:
		if not building_lists.has(value.town): building_lists[value.town] = []
		building_lists[value.town].append(value)

func end() -> void:
	active = false

func buildings(world, home: Dictionary) -> Array:
	if active: return building_lists.get(home.id, [])
	var result: Array = []
	for value in world.buildings:
		if value.town == home.id: result.append(value)
	return result

func building_added(value: Dictionary) -> void:
	if not active: return
	if not building_lists.has(value.town): building_lists[value.town] = []
	building_lists[value.town].append(value)

static func role(member: Dictionary) -> String:
	var kind: String = member.task.get("kind", "")
	if kind in ["gather_food", "fish"] or (kind == "deliver" and member.cargo_kind == "food"): return "food"
	if kind in ["plant", "harvest"]: return "farm"
	if kind == "gather_wood" or (kind == "deliver" and member.cargo_kind == "wood"): return "wood"
	if kind in ["build", "supply", "supply_goods"]: return "build"
	if kind in ["quarry", "manufacture"]: return "industry"
	return ""

static func base_need(world, member: Dictionary) -> float:
	var age: int = WorldLife.years(world, member)
	return (0.25 if age < 13 else (0.375 if age < 18 else 0.5)) * WorldEconomy.DAY_TICKS / WorldEconomy.NUTRITION

static func cold(world, cell: Vector2i) -> bool:
	return WorldClimate.biome(world, cell) >= 4 or (world.climate.seasons and WorldClimate.season(world) == 3)

func context(world, home: Dictionary) -> Dictionary:

	if not active or world.population_dirty:
		plans.clear(); contributions.clear()
	if plans.has(home.id): return plans[home.id]
	var residents: Array[Dictionary] = WorldEconomy.members(world, home)
	var result := {"population": 0, "food_workers": 0, "wood_workers": 0, "warm_need": 0.0, "cold_need": 0.0, "teams": {}, "available": {}, "resources": {}}
	plans[home.id] = result
	plan_builds += 1
	for member in residents:
		if WorldLife.adult(world, member): result.population += 1
		var need := base_need(world, member)
		result["cold_need" if cold(world, Vector2i(member.x, member.y)) else "warm_need"] += need
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

func daily_need(world, home: Dictionary) -> float:
	var plan := context(world, home)
	var data: Dictionary = WorldCivilization.get_data(world, home.id)
	var multiplier := 1.05 if not data.is_empty() and data.stock.cloth > 0 else 1.25
	return float(plan.warm_need) + float(plan.cold_need) * multiplier

func food_days(world, home: Dictionary) -> float:
	return float(home.food) / maxf(0.25, daily_need(world, home))

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
	return int(member.skills[skill]) * 4 + int(member.traits.diligence)

static func before(world, a: int, b: int, skill: String) -> bool:
	var left: Dictionary = world.person_index[a]
	var right: Dictionary = world.person_index[b]
	return score(left, skill) > score(right, skill) or (score(left, skill) == score(right, skill) and a < b)

static func update_rank(world, ids: Array, member: Dictionary, skill: String) -> void:
	ids.erase(int(member.id))
	if not member.task.is_empty() or member.cargo > 0 or not WorldLife.adult(world, member): return
	var first := 0
	var last := ids.size()
	while first < last:
		var mid := (first + last) / 2
		if before(world, int(ids[mid]), int(member.id), skill): first = mid + 1
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
		for other in WorldEconomy.members(world, home):
			if WorldLife.adult(world, other) and other.task.is_empty() and other.cargo == 0: ids.append(int(other.id))
		ids.sort_custom(func(a: int, b: int): return before(world, a, b, skill))
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
