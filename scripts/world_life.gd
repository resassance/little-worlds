class_name WorldLife
extends RefCounted

const YEAR := WorldEconomy.DAY_TICKS * WorldEconomy.DAYS_PER_YEAR
const MAX_HOUSEHOLDS := WorldState.MAX_PEOPLE
const MAX_ARCHIVE := 2048
const STAGES := ["Малыш", "Ребёнок", "Подросток", "Молодой взрослый", "Зрелый взрослый", "Пожилой"]

static func years(world, person: Dictionary) -> int:
	return maxi(0, (world.ticks - int(person.birth_tick)) / YEAR)

static func stage(world, person: Dictionary) -> int:
	var age: int = years(world, person)
	if age < 6: return 0
	if age < 13: return 1
	if age < 18: return 2
	if age < 40: return 3
	if age < 60: return 4
	return 5

static func adult(world, person: Dictionary) -> bool:
	return years(world, person) >= 18

static func hunger_rate(world, person: Dictionary) -> float:
	var age := years(world, person)
	return (0.25 if age < 13 else (0.375 if age < 18 else 0.5)) * WorldClimate.hunger_factor(world, person)

static func defaults(world, person: Dictionary) -> void:
	var initial_years: int = 18 + posmod(world.world_seed + int(person.id) * 5, 19)
	person.birth_tick = world.ticks - initial_years * YEAR
	person.sex = "female" if int(person.id) % 2 else "male"
	person.parents = []
	person.ancestors = []
	person.generation = 1
	person.guardian = -1
	person.partner = -1
	person.household = -1
	person.courting = -1
	person.bond = 0
	person.birth_due = -1
	person.last_birth = world.ticks - 2 * YEAR
	person.care_until = world.ticks
	person.health = 100.0
	WorldSocial.defaults(world, person)
	name_person(world, person)

static func name_person(world, person: Dictionary) -> void:
	var names: Array = ["Мира", "Лада", "Яна", "Ася", "Ника", "Вера"] if person.sex == "female" else ["Иван", "Тимур", "Роман", "Марк", "Лев", "Илья"]
	person.name = "%s %d" % [names[posmod(world.world_seed + int(person.id), names.size())], person.id]

static func person(world, id: int) -> Dictionary:
	return world.person_index.get(id, {})

static func household(world, id: int) -> Dictionary:
	return world.household_index.get(id, {})

static func related(a: Dictionary, b: Dictionary) -> bool:
	if a.id == b.id or a.ancestors.has(b.id) or b.ancestors.has(a.id): return true
	for id in a.ancestors:
		if b.ancestors.has(id): return true
	return false

static func household_members(world, value: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in value.members:
		var member := person(world, id)
		if not member.is_empty(): result.append(member)
	return result

static func new_household(world, member: Dictionary) -> Dictionary:
	if world.households.size() >= MAX_HOUSEHOLDS: return {}
	var value := {"id": world.next_id, "town": member.home, "dwelling": -1, "food": 0, "members": []}
	world.next_id += 1
	world.households.append(value)
	world.household_index[value.id] = value
	join(world, member, value)
	return value

static func join(world, member: Dictionary, value: Dictionary) -> void:
	var previous := household(world, member.household)
	if not previous.is_empty(): previous.members.erase(member.id)
	member.household = int(value.id)
	if not value.members.has(member.id): value.members.append(int(member.id))

static func dwelling_cell(world, value: Dictionary) -> Vector2i:
	var building := WorldEconomy.building(world, value.get("dwelling", -1))
	if building.is_empty():
		var home := WorldEconomy.town(world, value.get("town", -1))
		return Vector2i(home.x, home.y) if not home.is_empty() else WorldState.NO_CELL
	return Vector2i(building.x, building.y) + (Vector2i.ONE if building.kind == "house" else Vector2i.ZERO)

static func occupied_places(world, dwelling: int) -> int:
	if world.population.settling: return int(world.population.shelter_load.get(dwelling, 0))
	var total := 0
	for value in world.households:
		if value.dwelling == dwelling: total += value.members.size()
	return total

static func settle(world, value: Dictionary) -> void:
	var home := WorldEconomy.town(world, value.town)
	var current := WorldEconomy.building(world, value.dwelling)
	if home.is_empty():
		world.population.dwelling_changed(value, -1)
		return
	if not current.is_empty() and current.ready and current.town == home.id and current.kind == "house" and occupied_places(world, current.id) == value.members.size() and value.members.size() <= 4: return
	var previous: int = value.dwelling
	world.population.dwelling_changed(value, -1)

	for kind in ["house", "camp"]:
		for building in world.workforce.buildings(world, home):
			if building.town != home.id or building.kind != kind or not building.ready: continue
			if kind == "house" and occupied_places(world, building.id) > 0: continue
			if occupied_places(world, building.id) + value.members.size() > 4: continue
			if not WorldEconomy.navigation(world, home).parents.has(Vector2i(building.x, building.y)): continue
			world.population.dwelling_changed(value, int(building.id))
			return
	if not current.is_empty() and current.ready and current.town == home.id and occupied_places(world, previous) + value.members.size() <= 4: world.population.dwelling_changed(value, previous)

static func needs_home(world, home: Dictionary) -> bool:
	for value in world.households:
		if value.town != home.id or value.members.size() > 4: continue
		var shelter := WorldEconomy.building(world, value.dwelling)
		if not shelter.is_empty() and shelter.kind == "house": continue
		for member in household_members(world, value):
			if member.sex == "female" and member.partner != -1 and years(world, member) < 45: return true
	return false

static func clean_households(world) -> void:
	for i in range(world.households.size() - 1, -1, -1):
		var value: Dictionary = world.households[i]
		if not value.members.is_empty(): continue
		world.metrics.lost_food += value.food
		world.household_index.erase(value.id)
		world.households.remove_at(i)

static func choose_guardian(world, child: Dictionary) -> int:
	var home := WorldEconomy.town(world, child.home)
	if home.is_empty(): return -1
	var parents: Dictionary = WorldEconomy.navigation(world, home).parents
	if not parents.has(Vector2i(child.x, child.y)): return -1
	var best := -1
	var best_score := INF
	var loads := {}
	for child_member in WorldEconomy.members(world, home):
		if years(world, child_member) < 6: loads[child_member.guardian] = int(loads.get(child_member.guardian, 0)) + 1
	for candidate in WorldEconomy.members(world, home):
		if not adult(world, candidate) or not parents.has(Vector2i(candidate.x, candidate.y)): continue
		var load: int = int(loads.get(candidate.id, 0))
		var score: float = Vector2i(child.x, child.y).distance_squared_to(Vector2i(candidate.x, candidate.y)) + load * 100
		if child.parents.has(candidate.id): score -= 10000
		elif candidate.household == child.household and child.household != -1: score -= 1000
		if score < best_score:
			best_score = score
			best = int(candidate.id)
	return best

static func reconcile(world) -> void:
	var job := WorldLifeReconcileJob.new(world)
	while not job.finished: job.unit()

static func reconcile_member(world, member: Dictionary) -> void:
	var family := household(world, member.household)
	if family.is_empty():
		if not adult(world, member):
			var guardian := person(world, member.guardian)
			if guardian.is_empty() or guardian.home != member.home: member.guardian = choose_guardian(world, member)
			guardian = person(world, member.guardian)
			if not guardian.is_empty(): family = household(world, guardian.household)
		if family.is_empty(): family = new_household(world, member)
		elif member.household != family.id: join(world, member, family)
	elif family.town != member.home:

		if family.members.size() == 1:
			family.town = member.home
			family.dwelling = -1
		else: new_household(world, member)
	if adult(world, member):
		member.guardian = -1
		if member.job in ["child", "teen"]: member.job = "settler"
	else:
		var guardian := person(world, member.guardian)
		if guardian.is_empty() or not adult(world, guardian) or guardian.home != member.home:
			member.guardian = choose_guardian(world, member)
			guardian = person(world, member.guardian)
			if not guardian.is_empty():
				var adopted := household(world, guardian.household)
				if not adopted.is_empty(): join(world, member, adopted)
				world.log_event("Опека", "%s: заботу принял%s %s." % [member.name, "а" if guardian.sex == "female" else "", guardian.name])

static func reconcile_links(world, member: Dictionary) -> void:
	var mate := person(world, member.partner)
	if member.partner != -1 and (mate.is_empty() or member.home != mate.home):
		if not mate.is_empty():
			mate.partner = -1
			mate.birth_due = -1
		member.partner = -1
		member.birth_due = -1
	var courting := person(world, member.courting)
	if member.courting != -1 and (courting.is_empty() or member.home != courting.home):
		if not courting.is_empty():
			courting.courting = -1
			courting.bond = 0
		member.courting = -1
		member.bond = 0
	if member.task.get("kind", "") == "care":
		var child := person(world, member.task.dependent)
		if child.is_empty() or child.guardian != member.id or adult(world, child): WorldEconomy.set_task(world, member, {})


static func partner_valid(world, a: Dictionary, b: Dictionary) -> bool:
	return not b.is_empty() and adult(world, a) and adult(world, b) and a.home == b.home and a.sex != b.sex and not related(a, b)

static func make_pair(world, a: Dictionary, b: Dictionary) -> void:
	a.partner = int(b.id)
	b.partner = int(a.id)
	a.courting = -1
	b.courting = -1
	a.bond = 0
	b.bond = 0
	var family := household(world, a.household)
	if family.is_empty() or family.members.size() > 1: family = new_household(world, a)
	if family.is_empty():
		a.partner = -1
		b.partner = -1
		return
	join(world, b, family)

	for child in world.people:
		if child.guardian in [a.id, b.id] and not adult(world, child): join(world, child, family)
	clean_households(world)
	settle(world, family)
	world.log_event("Новая семья", "%s и %s решили жить вместе." % [a.name, b.name])

static func court(world) -> void:
	for home in world.towns:
		for member in WorldEconomy.members(world, home): court_member(world, home, member)

static func court_member(world, home: Dictionary, a: Dictionary) -> void:
	if WorldTravel.away(world, a.id): return
	if not adult(world, a) or a.partner != -1 or a.hunger > 40 or a.health < 60: return
	var candidate := person(world, a.courting)
	if candidate.is_empty() or WorldTravel.away(world,candidate.id) or candidate.partner != -1 or candidate.courting != a.id or not partner_valid(world, a, candidate):
		if not candidate.is_empty() and candidate.courting == a.id:
			candidate.courting = -1
			candidate.bond = 0
		a.courting = -1
		a.bond = 0
		candidate = {}
		var best_score := -INF
		for b in world.population.nearby(world, Vector2i(a.x, a.y), 9, home.id):
			if WorldTravel.away(world, b.id) or WorldSocial.tension(a,b)>=30 or b.partner != -1 or b.courting != -1 or b.hunger > 40 or not partner_valid(world, a, b): continue
			if absi(years(world, a) - years(world, b)) > 20: continue
			if Vector2i(a.x, a.y).distance_squared_to(Vector2i(b.x, b.y)) > 9: continue
			var score: float = WorldSocial.closeness(a, b) * 2 - absi(years(world, a) - years(world, b))
			if a.traits.sociability == b.traits.sociability: score += 4
			if score > best_score:
				best_score = score
				candidate = b
		if not candidate.is_empty():
			a.courting = int(candidate.id)
			candidate.courting = int(a.id)
			candidate.bond = 0
	if candidate.is_empty() or a.id > candidate.id: return
	if Vector2i(a.x, a.y).distance_squared_to(Vector2i(candidate.x, candidate.y)) <= 9:
		a.bond += 1
		candidate.bond = a.bond
	if a.bond >= 3: make_pair(world, a, candidate)


static func pending(world, dwelling: int = -1) -> int:
	var result := 0
	for member in world.people:
		if member.birth_due < 0: continue
		var family := household(world, member.household)
		if dwelling == -1 or (not family.is_empty() and family.dwelling == dwelling): result += 1
	return result

static func birth_conditions(world, mother: Dictionary, starting: bool) -> bool:
	var father := person(world, mother.partner)
	if mother.sex != "female" or not partner_valid(world, mother, father): return false
	if WorldTravel.away(world, mother.id) or WorldTravel.away(world, father.id): return false
	if years(world, mother) >= 45 or years(world, father) >= 60 or mother.health < 75 or father.health < 60 or mother.hunger >= 35 or father.hunger >= 35: return false
	if starting and (world.ticks - mother.last_birth < 2 * YEAR or mother.energy < 25 or father.energy < 25): return false
	var family := household(world, mother.household)
	if family.is_empty() or father.household != family.id: return false
	var shelter := WorldEconomy.building(world, family.dwelling)
	if shelter.is_empty() or not shelter.ready or shelter.kind != "house": return false
	var occupied: int = occupied_places(world, shelter.id)
	if occupied + pending(world, shelter.id) + (1 if starting else 0) > 4: return false
	if world.people.size() + (pending(world) if starting else 0) >= WorldState.MAX_PEOPLE: return false
	var home := WorldEconomy.town(world, mother.home)
	if home.is_empty() or WorldEconomy.food_days(world, home) < 8: return false
	if world.fires.has(Vector2i(shelter.x, shelter.y)): return false
	var young_children := 0
	for child in household_members(world, family):
		if years(world, child) < 6: young_children += 1
	return young_children < 2

static func give_birth(world, mother: Dictionary) -> bool:
	if mother.birth_due < 0 or world.ticks < mother.birth_due or not birth_conditions(world, mother, false): return false
	var family := household(world, mother.household)
	var location := dwelling_cell(world, family)
	if Vector2i(mother.x, mother.y).distance_squared_to(location) > 2: return false
	if not world.add_person(location, false): return false
	var father := person(world, mother.partner)
	var baby: Dictionary = world.people.back()

	world.metrics.spawn_food -= baby.rations
	baby.rations = 0
	baby.birth_tick = world.ticks
	WorldVocation.defaults(world, baby)
	baby.home = int(mother.home)


	baby.sex = "female" if (world.world_seed + int(world.metrics.births)) % 2 else "male"
	name_person(world, baby)
	baby.parents = [int(mother.id), int(father.id)]
	baby.ancestors = baby.parents.duplicate()
	for i in maxi(mother.ancestors.size(), father.ancestors.size()):
		for parent in [mother, father]:
			if i >= parent.ancestors.size(): continue
			var id: int = parent.ancestors[i]
			if not baby.ancestors.has(id) and baby.ancestors.size() < 14: baby.ancestors.append(id)
	baby.generation = maxi(mother.generation, father.generation) + 1
	baby.guardian = int(mother.id)
	baby.care_until = world.ticks + WorldEconomy.DAY_TICKS * 2
	baby.last_birth = world.ticks
	baby.job = "child"
	join(world, baby, family)
	mother.birth_due = -1
	mother.last_birth = world.ticks
	father.last_birth = world.ticks
	world.metrics.births += 1
	world.log_event("Рождение ребёнка", "%s: ребёнок %s у %s и %s." % [WorldEconomy.town(world, mother.home).name, baby.name, mother.name, father.name])
	return true

static func daily(world) -> void:
	reconcile(world)
	court(world)
	var ids: Array[int] = []
	for member in world.people: ids.append(int(member.id))
	for id in ids: daily_member(world, id)

static func daily_member(world, id: int) -> void:
	var member := person(world, id)
	if member.is_empty(): return
	var age: int = years(world, member)
	if age >= 60:
		var annual: float = 0.02 + pow(maxf(0, (age - 60) / 40.0), 3) * 0.6 + (100 - member.health) * 0.001
		if world.rng.randf() < minf(0.95, annual) / WorldEconomy.DAYS_PER_YEAR:
			world.remove_person(world.people.find(member), "старость")
			return
	if member.birth_due >= 0:
		var mate := person(world, member.partner)
		if not partner_valid(world, member, mate) or age >= 45:
			member.birth_due = -1
		else: give_birth(world, member)
	elif birth_conditions(world, member, true): member.birth_due = world.ticks + YEAR * 3 / 4


static func care_candidate(world, carer: Dictionary) -> Dictionary:
	if not adult(world, carer): return {}
	var best: Dictionary = {}
	var score := -INF
	for child in world.population.children(world, carer):
		if child.guardian != carer.id or adult(world, child): continue
		var family := household(world, child.household)
		var urgent: bool = (years(world, child) < 6 and child.care_until <= world.ticks + WorldEconomy.DAY_TICKS) or (child.hunger >= 20 and child.rations == 0 and (family.is_empty() or family.food == 0))
		if not urgent: continue
		var priority: float = child.hunger + (100 - child.health) + (50 if child.care_until < world.ticks else 0)
		if priority > score:
			best = child
			score = priority
	return best

static func assign_care(world, carer: Dictionary, home: Dictionary) -> bool:
	var child := care_candidate(world, carer)
	if child.is_empty(): return false
	WorldEconomy.set_task(world, carer, WorldEconomy.task("care", Vector2i(child.x, child.y)))
	carer.task.dependent = int(child.id)
	carer.job = "carer"
	return true

static func perform_care(world, carer: Dictionary, home: Dictionary) -> void:
	var active: Dictionary = carer.task
	var child := person(world, active.dependent)
	if child.is_empty() or child.guardian != carer.id or adult(world, child) or child.home != home.id:
		WorldEconomy.set_task(world, carer, {})
		return
	var family := household(world, child.household)
	var target := Vector2i(child.x, child.y)
	if not WorldEconomy.navigation(world, home).parents.has(target):
		WorldEconomy.set_task(world, carer, {})
		return

	if not family.is_empty() and family.food < 2 and carer.cargo == 0 and home.food > 0:
		if not WorldEconomy.move(world, carer, Vector2i(home.x, home.y), home): return
		var amount := mini(4 - int(family.food), int(home.food))
		home.food -= amount
		carer.cargo = amount
		carer.cargo_kind = "food"
		return
	active.x = target.x
	active.y = target.y
	if not WorldEconomy.move(world, carer, target, home): return
	active.work += 1
	carer.energy = maxf(0, carer.energy - 0.25)
	if active.work < 3: return
	if not family.is_empty() and carer.cargo_kind == "food":
		var delivered := mini(int(carer.cargo), maxi(0, 4 - int(family.food)))
		family.food += delivered
		carer.cargo -= delivered
		if carer.cargo == 0: carer.cargo_kind = ""
	if child.rations == 0 and child.hunger >= 20 and carer.rations > 0 and (family.is_empty() or family.food == 0):
		carer.rations -= 1
		child.rations = 1
	child.care_until = world.ticks + WorldEconomy.DAY_TICKS * 2
	child.health = minf(100, child.health + 4)
	WorldEconomy.set_task(world, carer, {})

static func dependent_step(world, child: Dictionary, home: Dictionary) -> void:
	child.job = "teen" if years(world, child) >= 13 else "child"
	if not child.task.is_empty(): WorldEconomy.set_task(world, child, {})
	if WorldSocial.student_step(world, child, home): return
	var family := household(world, child.household)
	var guardian := person(world, child.guardian)
	var location := dwelling_cell(world, family) if not family.is_empty() else WorldState.NO_CELL
	if location == WorldState.NO_CELL and not guardian.is_empty(): location = Vector2i(guardian.x, guardian.y)
	if not home.is_empty() and location != WorldState.NO_CELL:
		WorldEconomy.move(world, child, location, home)
	elif not guardian.is_empty():
		var current := Vector2i(child.x, child.y)
		var best := current
		var distance := current.distance_squared_to(location)
		for direction in WorldState.DIRECTIONS:
			var next: Vector2i = current + direction
			if world.walkable(next) and not world.fires.has(next) and next.distance_squared_to(location) < distance:
				best = next
				distance = best.distance_squared_to(location)
		child.x = best.x
		child.y = best.y
		world.track_person_move(child, current)

	if home.is_empty() and not guardian.is_empty() and Vector2i(child.x, child.y).distance_squared_to(Vector2i(guardian.x, guardian.y)) <= 2:
		child.care_until = world.ticks + WorldEconomy.DAY_TICKS * 2
		if child.hunger >= 20 and child.rations == 0 and guardian.rations > 1:
			guardian.rations -= 1
			child.rations = 1
	if not family.is_empty() and child.rations == 0 and family.food > 0 and Vector2i(child.x, child.y).distance_squared_to(location) <= 2:
		family.food -= 1
		child.rations = 1
	if years(world, child) < 6 and child.care_until < world.ticks:
		child.health = maxf(0, child.health - 0.125)
	else: child.health = minf(100, child.health + 0.125)
	child.energy = minf(100, child.energy + 1)

static func archive_death(world, member: Dictionary, cause: String) -> void:
	WorldSocial.remove(world, member)
	var record := {"id": member.id, "name": member.name, "birth_tick": member.birth_tick, "death_tick": world.ticks, "parents": member.parents.duplicate(), "generation": member.generation, "cause": cause}
	record.skills = member.skills.duplicate()
	world.ancestry_archive.append(record)
	if world.ancestry_archive.size() > MAX_ARCHIVE: world.ancestry_archive.pop_front()
	world.metrics.deaths += 1
	for other in world.people:
		if other.partner == member.id:
			other.partner = -1
			other.birth_due = -1
		if other.courting == member.id:
			other.courting = -1
			other.bond = 0
		if other.guardian == member.id: other.guardian = -1
		if other.task.get("dependent", -1) == member.id: WorldEconomy.set_task(world, other, {})
	var family := household(world, member.household)
	if not family.is_empty(): family.members.erase(member.id)
	clean_households(world)

static func label(world, id: int) -> String:
	var living := person(world, id)
	if not living.is_empty(): return living.name
	for record in world.ancestry_archive:
		if record.id == id: return record.name + " †"
	return "Предок №%d" % id

static func population_summary(world, home: Dictionary) -> String:
	var children := 0
	var workers := 0
	var elders := 0
	for member in WorldEconomy.members(world, home):
		if not adult(world, member): children += 1
		else:
			workers += 1
			if years(world, member) >= 60: elders += 1
	return "Взрослые: %d · дети: %d · пожилые: %d" % [workers, children, elders]

static func family_description(world, member: Dictionary) -> String:
	var text := "Поколение %d" % member.generation
	if member.partner != -1: text += "\nПартнёр: " + label(world, member.partner)
	if not member.parents.is_empty(): text += "\nРодители: %s, %s" % [label(world, member.parents[0]), label(world, member.parents[1])]
	if member.guardian != -1: text += "\nОпекун: " + label(world, member.guardian)
	var family := household(world, member.household)
	if not family.is_empty():
		text += "\nСемья: %d человек · еда: %d" % [family.members.size(), family.food]
		var dwelling := WorldEconomy.building(world, family.dwelling)
		text += "\nЖильё: " + (WorldEconomy.NAMES[dwelling.kind] if not dwelling.is_empty() else "ищет место")
	if member.birth_due >= 0: text += "\nВ семье ждут ребёнка"
	return text

static func integer_ids(value: Variant, maximum: int, next_id: int) -> bool:
	if not value is Array or value.size() > maximum: return false
	var used := {}
	for id in value:
		if not WorldState._integer(id) or id <= 0 or id >= next_id or used.has(int(id)): return false
		used[int(id)] = true
	return true

static func restore(world, data: Dictionary) -> bool:
	if not data.get("households") is Array or data.households.size() > MAX_HOUSEHOLDS: return false
	if not data.get("ancestry_archive") is Array or data.ancestry_archive.size() > MAX_ARCHIVE: return false
	var ids := {}
	for member in world.people: ids[member.id] = true
	for home in world.towns: ids[home.id] = true
	for building in world.buildings: ids[building.id] = true
	var archive_ids := {}
	for source in data.ancestry_archive:
		if not source is Dictionary or not source.get("name") is String or not source.get("cause") is String: return false
		for key in ["id", "birth_tick", "death_tick", "generation"]:
			if not WorldState._integer(source.get(key)): return false
		if source.id <= 0 or source.id >= world.next_id or ids.has(int(source.id)) or archive_ids.has(int(source.id)): return false
		if source.birth_tick > source.death_tick or source.death_tick > world.ticks or source.generation < 1: return false
		if not integer_ids(source.get("parents"), 2, world.next_id) or source.parents.size() not in [0, 2] or source.parents.has(source.id): return false
		var record: Dictionary = source.duplicate(true)
		for key in ["id", "birth_tick", "death_tick", "generation"]: record[key] = int(record[key])
		for i in record.parents.size(): record.parents[i] = int(record.parents[i])
		archive_ids[record.id] = record
		world.ancestry_archive.append(record)
	var membership := {}
	var slots := {}
	for source in data.households:
		if not source is Dictionary: return false
		for key in ["id", "town", "dwelling", "food"]:
			if not WorldState._integer(source.get(key)): return false
		if source.id <= 0 or source.id >= world.next_id or ids.has(int(source.id)) or archive_ids.has(int(source.id)): return false
		if source.food < 0 or source.food > 4 or not integer_ids(source.get("members"), WorldState.MAX_PEOPLE, world.next_id) or source.members.is_empty(): return false
		if source.town != -1 and WorldEconomy.town(world, source.town).is_empty(): return false
		var value: Dictionary = source.duplicate(true)
		for key in ["id", "town", "dwelling", "food"]: value[key] = int(value[key])
		for i in value.members.size():
			var id: int = value.members[i]
			var member := person(world, id)
			if member.is_empty() or membership.has(id) or member.home != value.town: return false
			value.members[i] = id
			membership[id] = value.id
		if value.dwelling != -1:
			var shelter := WorldEconomy.building(world, value.dwelling)
			if shelter.is_empty() or not shelter.ready or shelter.kind not in ["camp", "house"] or shelter.town != value.town: return false
			slots[value.dwelling] = int(slots.get(value.dwelling, 0)) + value.members.size()
			if slots[value.dwelling] > 4: return false
		ids[value.id] = true
		world.households.append(value)
		world.household_index[value.id] = value
	for member in world.people:
		for key in ["birth_tick", "generation", "guardian", "partner", "household", "courting", "bond", "birth_due", "last_birth", "care_until"]:
			if not WorldState._integer(member.get(key)): return false
			member[key] = int(member[key])
		if member.birth_tick > world.ticks or member.generation < 1 or member.bond < 0 or member.bond > 3 or member.birth_due < -1 or member.last_birth > world.ticks or member.care_until < 0: return false
		if member.get("sex") not in ["female", "male"]: return false
		if not integer_ids(member.get("parents"), 2, world.next_id) or member.parents.size() not in [0, 2] or member.parents.has(member.id): return false
		if not integer_ids(member.get("ancestors"), 14, world.next_id) or member.ancestors.has(member.id): return false
		for i in member.parents.size(): member.parents[i] = int(member.parents[i])
		for i in member.ancestors.size(): member.ancestors[i] = int(member.ancestors[i])
		if not (member.get("health") is float or member.get("health") is int) or not is_finite(float(member.health)) or member.health <= 0 or member.health > 100: return false
		member.health = float(member.health)
		if member.household != membership.get(member.id, -1): return false
		if member.household == -1: world.life_dirty = true
	for member in world.people:
		for parent_id in member.parents:
			if not member.ancestors.has(parent_id): return false
			var parent := person(world, parent_id)
			if parent.is_empty(): parent = archive_ids.get(parent_id, {})
			if not parent.is_empty() and (parent.birth_tick >= member.birth_tick or parent.generation >= member.generation): return false
		if member.partner != -1:
			var mate := person(world, member.partner)
			if not partner_valid(world, member, mate) or mate.partner != member.id or mate.household != member.household: return false
		if member.courting != -1:
			var candidate := person(world, member.courting)
			if not partner_valid(world, member, candidate) or member.partner != -1 or candidate.courting != member.id or candidate.bond != member.bond: return false
		if member.guardian != -1:
			var guardian := person(world, member.guardian)
			if guardian.is_empty() or not adult(world, guardian) or adult(world, member) or guardian.home != member.home: return false
		if member.birth_due >= 0 and (member.sex != "female" or not adult(world, member) or member.partner == -1): return false
		if not adult(world, member) and (member.cargo != 0 or (not member.task.is_empty() and member.task.get("kind", "") != "travel")): return false
		if member.task.get("kind", "") == "care":
			if not WorldState._integer(member.task.get("dependent")): return false
			member.task.dependent = int(member.task.dependent)
			var child := person(world, member.task.dependent)
			if child.is_empty() or child.guardian != member.id or adult(world, child): return false
	return true
