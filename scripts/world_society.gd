class_name WorldSociety
extends RefCounted

const ERAS := ["Община", "Оседлое поселение", "Развитая деревня", "Ремесленное поселение", "Ранний город", "Средневековое общество"]
const LIMIT := 1000000
static var TECH: Dictionary = WorldDevelopment.METHODS

static func get_society(world, town_id: int) -> Dictionary:
	return world.society_index.get(town_id, {})

static func ensure_town(world, home: Dictionary) -> Dictionary:
	var society := get_society(world, home.id)
	if not society.is_empty(): return society
	society = {"id": world.next_id, "town": int(home.id), "name": "Община «%s»" % home.name, "era": 0, "era_days": 0, "project": "", "worker": -1, "taught": 0, "practice": {"food": 0, "wood": 0, "build": 0, "farm": 0}, "tech": {}}
	world.next_id += 1
	for key in TECH: society.tech[key] = {"known": false, "mastered": false, "progress": 0, "used": 0, "discovered_tick": -1, "operating": false}
	WorldDevelopment.initialize(world, society)
	world.societies.append(society)
	world.society_index[home.id] = society
	return society

static func invalidate(world) -> void:
	world.society_cache.clear()

static func remember(member: Dictionary, key: String) -> void:
	if not member.ideas.has(key): member.ideas.append(key)

static func practice(world, member: Dictionary, skill: String) -> void:
	var society := get_society(world, member.home)
	if society.is_empty(): return
	society.practice[skill] = mini(LIMIT, int(society.practice[skill]) + 1)
	WorldDevelopment.practice(society, member, skill)
	for key in TECH:
		if society.tech[key].mastered and (TECH[key].skill == skill or TECH[key].experts.has(skill)): remember(member, key)

static func mastered(world, home: Dictionary, key: String) -> bool:
	var society := get_society(world, home.id)
	return not society.is_empty() and society.tech[key].mastered

static func experts(world, home: Dictionary) -> Dictionary:
	var cached: Dictionary = world.society_cache.get(home.id, {})
	if cached.get("tick", -1) == world.ticks: return cached.skills
	var skills := {"food": 0, "wood": 0, "build": 0, "farm": 0}
	for member in WorldEconomy.members(world, home):
		if WorldTravel.away(world, member.id): continue
		if not WorldLife.adult(world, member) or member.health < 60 or member.hunger >= 40: continue
		if not WorldEconomy.navigation(world, home).parents.has(Vector2i(member.x, member.y)): continue
		for skill in skills: skills[skill] = maxi(int(skills[skill]), int(member.skills[skill]))
	world.society_cache[home.id] = {"tick": world.ticks, "skills": skills}
	return skills

static func reason(world, home: Dictionary, key: String, applying: bool = false) -> String:
	var spec: Dictionary = TECH[key]
	if spec.get("coastal", false) and WorldEconomy.navigation(world, home).coasts.is_empty(): return "нужен доступный берег"
	var equipped := false
	for kind in spec.sites:
		if WorldEconomy.count(world, home, kind) > 0: equipped = true
	if not equipped: return "нужно рабочее место: " + WorldEconomy.NAMES[spec.sites[0]]
	if not applying:
		var state: Dictionary = get_society(world, home.id).tech[key]
		if state.retry_tick > world.ticks: return "после неудачного опыта нужен перерыв"
		if not state.spent:
			for resource in spec.inputs:
				if not WorldCivilization.inputs_available(world, home, {resource: spec.inputs[resource]}):
					return "нужен материал для опытов: " + {"wood": "древесина", "food": "пища"}.get(resource, WorldCivilization.GOODS.get(resource, resource))
	if applying and key == "records" and WorldEconomy.count(world, home, "archive") == 0: return "нужен архив"
	var available := experts(world, home)
	for skill in spec.experts:
		if available[skill] < spec.experts[skill]: return "нужен опытный специалист: " + WorldSocial.SKILLS[skill]
	return ""

static func active(world, home: Dictionary, key: String) -> bool:
	return mastered(world, home, key) and reason(world, home, key, true).is_empty()

static func use(world, home: Dictionary, key: String, member: Dictionary = {}) -> void:
	var society := get_society(world, home.id)
	if society.is_empty() or not society.tech[key].mastered: return
	society.tech[key].used = mini(LIMIT, int(society.tech[key].used) + 1)
	if not member.is_empty(): remember(member, key)

static func research_assign(world, member: Dictionary, home: Dictionary) -> bool:
	var society := get_society(world, home.id)
	if society.is_empty() or society.project.is_empty() or society.worker != -1: return false
	var key: String = society.project
	if member.skills[TECH[key].skill] < int(TECH[key].experts.get(TECH[key].skill, 40)) or member.energy < 30 or member.health < 70 or member.hunger >= 25 or WorldEconomy.food_days(world, home) < 6: return false
	if not reason(world, home, key).is_empty(): return false
	society.worker = int(member.id)
	WorldEconomy.set_task(world, member, WorldEconomy.task("research", Vector2i(home.x, home.y)))
	member.task.society = int(society.id)
	member.task.tech = key
	member.job = "researcher"
	return true

static func stop(world, member: Dictionary) -> void:
	var society := get_society(world, member.home)
	if society.is_empty() or society.id != member.task.get("society", -1):
		for value in world.societies:
			if value.id == member.task.get("society", -1):
				society = value
				break
	if not society.is_empty() and society.worker == member.id: society.worker = -1

static func research(world, member: Dictionary, home: Dictionary) -> void:
	var society := get_society(world, home.id)
	var key: String = member.task.tech
	if society.is_empty() or society.worker != member.id or society.project != key or not TECH.has(key):
		WorldEconomy.set_task(world, member, {})
		return
	if WorldEconomy.food_days(world, home) < 3 or member.hunger >= 30 or member.health < 60 or member.energy < 18 or not reason(world, home, key).is_empty():
		WorldEconomy.set_task(world, member, {})
		return
	var location := Vector2i(home.x, home.y)
	if world.fires.has(location) or not WorldEconomy.move(world, member, location, home): return
	member.task.work += 1
	member.energy = maxf(0, member.energy - 0.5)
	var state: Dictionary = society.tech[key]
	world.metrics.research_work += 1
	WorldSocial.practice(world, member, TECH[key].skill)
	var succeeded := WorldDevelopment.experiment(world, home, society, key, member)
	if not succeeded: return
	state.progress = int(TECH[key].work)
	state.mastered = true
	state.discovered_tick = world.ticks
	world.metrics.discoveries += 1
	remember(member, key)
	world.log_event("Освоена технология", "%s: %s. Можно применять в хозяйстве." % [home.name, TECH[key].name])
	WorldEconomy.set_task(world, member, {})
	society.project = ""
	society.project_reason = ""
	invalidate(world)

static func taught(world, mentor: Dictionary, student: Dictionary) -> void:
	var society := get_society(world, mentor.home)
	if society.is_empty(): return
	society.taught = mini(LIMIT, int(society.taught) + 1)
	society.domain_practice.education = mini(LIMIT, int(society.domain_practice.education) + 1)
	for key in mentor.ideas: remember(student, key)

static func daily(world) -> void:
	for home in world.towns: daily_town(world, home)

static func daily_town(world, home: Dictionary) -> void:
	var society := ensure_town(world, home)

	for member in WorldEconomy.members(world, home):
		if WorldTravel.away(world, member.id): continue
		if not WorldEconomy.navigation(world, home).parents.has(Vector2i(member.x, member.y)): continue
		for key in member.ideas:
			if not society.tech[key].known:
				society.tech[key].known = true
				world.log_event("Новая идея", "%s: %s прин%s знание «%s»." % [home.name, member.name, "есла" if member.sex == "female" else "ёс", TECH[key].name])
	for key in TECH:
		var state: Dictionary = society.tech[key]
		if state.mastered:
			var operating := active(world, home, key)
			if state.operating != operating:
				state.operating = operating
				world.log_event("Технология в деле" if operating else "Ремесло простаивает", "%s: %s%s." % [home.name, TECH[key].name, "" if operating else " — " + reason(world, home, key, true)])
		if society.tech[key].known: continue
		var enough := true
		for skill in TECH[key].practice:
			if society.practice[skill] < TECH[key].practice[skill]: enough = false
		if enough:
			society.tech[key].known = true
			world.log_event("Идея общины", "%s: практика подсказала «%s». Нужно выделить время на освоение." % [home.name, TECH[key].name])
	if society.worker == -1 and not society.project.is_empty() and not reason(world, home, society.project).is_empty():
		society.project = ""
		society.project_reason = ""
	if society.worker == -1 and society.project.is_empty(): WorldDevelopment.choose(world, home, society)

static func reconcile(world) -> void:
	for i in range(world.societies.size() - 1, -1, -1):
		var society: Dictionary = world.societies[i]
		if not WorldEconomy.town(world, society.town).is_empty(): continue
		for member in world.people:
			if member.task.get("society", -1) == society.id: WorldEconomy.set_task(world, member, {})
		world.society_index.erase(society.town)
		world.societies.remove_at(i)
	invalidate(world)

static func description(world, home: Dictionary) -> String:
	var society := get_society(world, home.id)
	if society.is_empty(): return ""
	var text: String = "\n\n%s" % society.name
	var directions := WorldDevelopment.profile(world, home)
	for domain in directions:
		var value: Dictionary = directions[domain]
		if value.known == 0 and value.practice == 0: continue
		if value.known > 0:
			text += "\n%s: %d освоено · %d работает" % [WorldDevelopment.DOMAINS[domain], value.mastered, value.operating]
		else: text += "\n%s: есть практический опыт" % WorldDevelopment.DOMAINS[domain]
	if not society.project.is_empty():
		text += "\nПроект: %s\n%s" % [TECH[society.project].name, society.project_reason]
	if society.era > 0: text += "\nВ прежней хронике: " + ERAS[society.era]
	for key in TECH:
		var state: Dictionary = society.tech[key]
		if not state.known: continue
		var status := "нужна местная практика"
		if state.known:
			var why := reason(world, home, key, state.mastered)
			if state.mastered: status = ("применяется" if state.used > 0 else "готово к применению") if why.is_empty() else "освоено · " + why
			elif not why.is_empty(): status = why
			elif WorldEconomy.food_days(world, home) < 6: status = "нужен запас еды на 6 дней"
			else: status = "опыты: %d шагов · попытка %d" % [state.work_done, state.attempts]
		text += "\n%s: %s" % [TECH[key].name, status]
	text += "\nМастерские: %d · Архивы: %d" % [WorldEconomy.count(world, home, "workshop"), WorldEconomy.count(world, home, "archive")]
	return text

static func restore(world, data: Dictionary) -> bool:
	if not data.get("societies") is Array or data.societies.size() != world.towns.size(): return false
	var ids := {}
	for values in [world.people, world.towns, world.buildings, world.households, world.ancestry_archive]:
		for value in values: ids[int(value.id)] = true
	for source in data.societies:
		if not source is Dictionary or not source.get("name") is String: return false
		for key in ["id", "town", "era", "era_days", "worker", "taught"]:
			if not WorldState._integer(source.get(key)): return false
		if source.id <= 0 or source.id >= world.next_id or ids.has(int(source.id)) or world.society_index.has(int(source.town)) or WorldEconomy.town(world, source.town).is_empty(): return false
		if source.era < 0 or source.era >= ERAS.size() or source.era_days < 0 or source.era_days >= 3 or source.taught < 0 or source.taught > LIMIT: return false
		if not source.get("practice") is Dictionary or source.practice.size() != WorldSocial.SKILLS.size() or not source.get("tech") is Dictionary: return false
		if data.version >= 7 and source.tech.size() != TECH.size(): return false
		var society: Dictionary = source.duplicate(true)
		if data.version < 7:
			for key in TECH:
				if not society.tech.has(key): society.tech[key] = {"known": false, "mastered": false, "progress": 0, "used": 0, "discovered_tick": -1, "operating": false}
		for key in ["id", "town", "era", "era_days", "worker", "taught"]: society[key] = int(society[key])
		for skill in WorldSocial.SKILLS:
			if not WorldState._integer(society.practice.get(skill)) or society.practice[skill] < 0 or society.practice[skill] > LIMIT: return false
			society.practice[skill] = int(society.practice[skill])
		for key in TECH:
			var state: Variant = society.tech.get(key)
			if not state is Dictionary or not state.get("known") is bool or not state.get("mastered") is bool or not state.get("operating") is bool: return false
			for field in ["progress", "used", "discovered_tick"]:
				if not WorldState._integer(state.get(field)): return false
				state[field] = int(state[field])
			if state.progress < 0 or state.progress > int(TECH[key].work) or state.used < 0 or state.used > LIMIT: return false
			if not state.known and (state.progress > 0 or state.mastered): return false
			if state.mastered:
				if state.progress != int(TECH[key].work) or state.discovered_tick < 0 or state.discovered_tick > world.ticks: return false
			elif (data.version < 10 and state.progress == int(TECH[key].work)) or state.used > 0 or state.discovered_tick != -1: return false
		if not WorldDevelopment.restore(society, int(data.version), world): return false
		if not society.get("project") is String or (not society.project.is_empty() and (not TECH.has(society.project) or not society.tech[society.project].known or society.tech[society.project].mastered)): return false
		if society.era >= 1:
			for key in ["carpentry", "preservation"]:
				if not society.tech[key].mastered or society.tech[key].used == 0: return false
		if society.era >= 2 and not ((society.tech.rotation.mastered and society.tech.rotation.used > 0) or society.tech.records.mastered): return false
		if society.era >= 3 and (not society.tech.records.mastered or society.tech.records.used == 0 or society.taught == 0): return false
		if society.era >= 4 and (not society.tech.metallurgy.mastered or society.tech.metallurgy.used == 0 or not society.tech.governance.mastered): return false
		ids[society.id] = true
		world.societies.append(society)
		world.society_index[society.town] = society
	for society in world.societies:
		if society.worker == -1: continue
		var worker := WorldLife.person(world, society.worker)
		if worker.is_empty() or worker.home != society.town or not WorldLife.adult(world, worker) or society.project.is_empty() or worker.task.get("kind", "") != "research" or worker.task.get("society", -1) != society.id or worker.task.get("tech", "") != society.project: return false
	for member in world.people:
		if not member.get("ideas") is Array or member.ideas.size() > TECH.size(): return false
		var used := {}
		for key in member.ideas:
			if not key is String or not TECH.has(key) or used.has(key): return false
			used[key] = true
		if member.task.get("kind", "") != "research": continue
		if not WorldState._integer(member.task.get("society")) or not TECH.has(member.task.get("tech")): return false
		member.task.society = int(member.task.society)
		var society := get_society(world, member.home)
		if society.is_empty() or society.worker != member.id or society.id != member.task.society or society.project != member.task.tech or member.task.work > maxi(int(society.tech[society.project].progress), int(TECH[society.project].work) * 2): return false
	for value in world.buildings:
		if value.kind == "farm" and value.stock > 18 and not mastered(world, WorldEconomy.town(world, value.town), "rotation") and (data.version < 7 or world.metrics.crop_food < value.stock): return false
	return true
