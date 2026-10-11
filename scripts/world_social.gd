class_name WorldSocial
extends RefCounted

const SKILLS := {"food": "Собирательство", "wood": "Лесное дело", "build": "Строительство", "farm": "Земледелие"}
const TRAITS := ["sociability", "diligence", "curiosity"]
const MAX_LINKS := 8
const MAX_XP := 240
const FRIEND := 12
const LESSON_WORK := 10

static func defaults(world, member: Dictionary) -> void:
	member.ideas = []
	member.skills = {"food": 0, "wood": 0, "build": 0, "farm": 0}
	member.traits = {}
	for trait_key in TRAITS: member.traits[trait_key] = posmod(hash("%d:%d:%s" % [world.world_seed, member.id, trait_key]), 3)
	member.links = []
	member.rivals = []
	member.social_need = 0.0
	member.lesson = {}
	member.trained_by = {}

static func level(member: Dictionary, skill: String) -> int:
	var xp: int = member.skills[skill]
	return 3 if xp >= 120 else (2 if xp >= 40 else (1 if xp >= 10 else 0))

static func relation(member: Dictionary, id: int) -> Dictionary:
	for link in member.links:
		if link.id == id: return link
	return {}

static func closeness(a: Dictionary, b: Dictionary) -> int:
	return int(relation(a, b.id).get("bond", 0))

static func near(a: Dictionary, b: Dictionary, radius_squared: int = 9) -> bool:
	return a.home == b.home and Vector2i(a.x, a.y).distance_squared_to(Vector2i(b.x, b.y)) <= radius_squared

static func rivalry(member: Dictionary, id: int) -> Dictionary:
	for value in member.get("rivals",[]):
		if value.id==id: return value
	return {}

static func tension(a: Dictionary, b: Dictionary) -> int:
	return int(rivalry(a,b.id).get("resentment",0))

static func dispute(world, a: Dictionary, b: Dictionary, home: Dictionary) -> void:
	if not WorldLife.adult(world,a) or not WorldLife.adult(world,b) or a.household==b.household or not near(a,b,2): return
	if a.hunger<35 or b.hunger<35 or WorldEconomy.food_days(world,home)>=2: return
	var value:=rivalry(a,b.id)
	if value.is_empty():
		if a.rivals.size()>=4 or b.rivals.size()>=4: return
		value={"id":int(b.id),"resentment":0,"last_tick":-WorldEconomy.DAY_TICKS}
		a.rivals.append(value); b.rivals.append({"id":int(a.id),"resentment":0,"last_tick":-WorldEconomy.DAY_TICKS})
	if int(value.last_tick)/WorldEconomy.DAY_TICKS==world.ticks/WorldEconomy.DAY_TICKS: return
	var before: int=value.resentment
	value.resentment=mini(100,before+5); value.last_tick=world.ticks
	var reverse:=rivalry(b,a.id); reverse.resentment=value.resentment; reverse.last_tick=world.ticks
	if before<30 and value.resentment>=30: world.log_event("Разлад в общине","%s и %s перестали сотрудничать после продолжительной нехватки еды." % [a.name,b.name])

static func room(member: Dictionary) -> bool:
	return member.links.size() < MAX_LINKS

static func contact(world, a: Dictionary, b: Dictionary, amount: int = 1) -> void:
	if a.id == b.id or not near(a, b) or a.hunger >= 40 or b.hunger >= 40: return
	var rival:=rivalry(a,b.id)
	if not rival.is_empty() and amount>=2:
		rival.resentment=maxi(1,int(rival.resentment)-amount)
		rivalry(b,a.id).resentment=rival.resentment
	var link := relation(a, b.id)
	var reverse := relation(b, a.id)
	if link.is_empty():
		if not room(a) or not room(b): return
		link = {"id": int(b.id), "bond": 0, "last_tick": -WorldEconomy.DAY_TICKS}
		reverse = {"id": int(a.id), "bond": 0, "last_tick": -WorldEconomy.DAY_TICKS}
		a.links.append(link)
		b.links.append(reverse)
	if int(link.last_tick) / WorldEconomy.DAY_TICKS == world.ticks / WorldEconomy.DAY_TICKS: return
	var was_friend: bool = link.bond >= FRIEND
	link.bond = mini(100, int(link.bond) + amount)
	link.last_tick = world.ticks
	reverse.bond = link.bond
	reverse.last_tick = world.ticks
	a.social_need = maxf(0, a.social_need - 6 * amount)
	b.social_need = maxf(0, b.social_need - 6 * amount)
	if not was_friend and link.bond >= FRIEND and WorldLife.years(world, a) >= 6 and WorldLife.years(world, b) >= 6:
		world.log_event("Дружба", "%s и %s стали ближе." % [a.name, b.name])

static func practice(world, member: Dictionary, skill: String) -> void:
	var before: int = level(member, skill)
	var amount := 1 + (1 if member.traits.diligence == 2 and (world.ticks + int(member.id)) % 4 == 0 else 0)
	member.skills[skill] = mini(MAX_XP, int(member.skills[skill]) + amount)
	world.workforce.skill_changed(world, member, skill)
	WorldSociety.practice(world, member, skill)
	if before != level(member, skill): WorldSociety.invalidate(world)
	if before < 3 and level(member, skill) == 3:
		world.log_event("Мастер ремесла", "%s: %s." % [member.name, SKILLS[skill]])

static func task_skill(kind: String) -> String:
	return {"gather_food": "food", "gather_wood": "wood", "build": "build", "plant": "farm", "harvest": "farm"}.get(kind, "")

static func work_credit(world, member: Dictionary, skill: String) -> int:
	return 2 if level(member, skill) >= 2 and (world.ticks + int(member.id)) % (3 if level(member, skill) == 3 else 4) == 0 else 1

static func preferred(world, member: Dictionary, home: Dictionary, skill: String) -> bool:

	if WorldEconomy.food_days(world, home) < 6: return true
	if world.workforce.active: return world.workforce.preferred(world, member, home, skill)
	var best_id: int = member.id
	var best: int = int(member.skills[skill]) * 4 + int(member.traits.diligence)
	for other in WorldEconomy.members(world, home):
		if other.id == member.id or not WorldLife.adult(world, other) or other.cargo > 0 or not other.task.is_empty() or other.hunger >= 35 or other.energy < 18: continue
		if not WorldLife.care_candidate(world, other).is_empty() or other.birth_due >= 0: continue
		var score: int = int(other.skills[skill]) * 4 + int(other.traits.diligence)
		if score > best or (score == best and other.id < best_id):
			best = score
			best_id = other.id
	return member.id == best_id

static func visit_target(world, member: Dictionary, home: Dictionary) -> Vector2i:
	var target := Vector2i(home.x, home.y)
	var strongest := 0
	for link in member.links:
		var friend := WorldLife.person(world, link.id)
		if friend.is_empty() or friend.home != member.home or link.bond < FRIEND or link.bond <= strongest: continue
		var cell := Vector2i(friend.x, friend.y)
		if not WorldEconomy.navigation(world, home).parents.has(cell) or world.fires.has(cell): continue
		strongest = int(link.bond)
		target = cell
	return target

static func help(world, donor: Dictionary) -> void:
	if donor.rations < 2 or donor.hunger >= 20: return
	for link in donor.links:
		var receiver := WorldLife.person(world, link.id)
		if receiver.is_empty() or not near(donor, receiver, 2) or receiver.rations > 0 or receiver.hunger < 35 or receiver.cargo_kind == "food": continue
		if tension(donor,receiver)>=30 or (link.bond < FRIEND and receiver.household != donor.household): continue
		donor.rations -= 1
		receiver.rations += 1
		world.metrics.helped_food += 1
		contact(world, donor, receiver, 3)
		return

static func finish_visit(world, member: Dictionary, home: Dictionary) -> void:
	var met := 0
	for other in world.population.nearby(world, Vector2i(member.x, member.y), 9, home.id, {"limit": 3, "exclude_id": member.id}):
		if other.id == member.id or not near(member, other): continue
		contact(world, member, other, 2)
		met += 1
		if met >= 3: break
	help(world, member)

static func cancel_lesson(world, student: Dictionary) -> void:
	if student.lesson.is_empty(): return
	var mentor := WorldLife.person(world, student.lesson.mentor)
	if not mentor.is_empty() and mentor.task.get("kind", "") == "teach" and mentor.task.get("dependent", -1) == student.id: WorldEconomy.set_task(world, mentor, {})
	student.lesson = {}

static func eligible(world, student: Dictionary, mentor: Dictionary, skill: String) -> bool:
	if WorldTravel.away(world, student.id) or WorldTravel.away(world, mentor.id): return false
	if tension(student,mentor)>=30: return false
	if mentor.is_empty() or student.id == mentor.id or student.home == -1 or student.home != mentor.home: return false
	var age: int = WorldLife.years(world, student)
	var school: bool = WorldEconomy.count(world, WorldEconomy.town(world, student.home), "school") > 0
	if age < 6 or (age >= 18 and not school) or not WorldLife.adult(world, mentor) or mentor.skills[skill] < 40: return false
	if student.skills[skill] >= (120 if age >= 18 else (80 if age >= 13 else 30)) or mentor.skills[skill] < student.skills[skill] + 10: return false
	if student.hunger >= 30 or mentor.hunger >= 30 or student.health < 60 or mentor.health < 60 or mentor.energy < 18: return false
	var home := WorldEconomy.town(world, student.home)
	return not home.is_empty() and WorldEconomy.food_days(world, home) >= 3

static func offer_lesson(world, student: Dictionary, home: Dictionary) -> bool:
	if not student.lesson.is_empty() or student.hunger >= 25 or student.rations == 0: return false
	var best: Dictionary = {}
	var best_skill := ""
	var score := -INF
	for mentor in WorldEconomy.members(world, home):
		if WorldTravel.away(world, mentor.id): continue
		if mentor.cargo > 0 or mentor.energy < 40 or mentor.birth_due >= 0: continue
		if not mentor.task.is_empty() and mentor.task.kind not in ["rest", "visit"]: continue
		if not WorldLife.care_candidate(world, mentor).is_empty(): continue
		for skill in SKILLS:
			if not eligible(world, student, mentor, skill): continue
			var rank: float = mentor.skills[skill] - student.skills[skill] + closeness(student, mentor) + (30 if mentor.household == student.household else 0)

			if (posmod(world.world_seed + int(student.id), SKILLS.size()) == SKILLS.keys().find(skill)) and student.traits.curiosity == 2: rank += 30
			if rank > score:
				score = rank
				best = mentor
				best_skill = skill
	if best.is_empty(): return false
	student.lesson = {"mentor": int(best.id), "skill": best_skill, "work": 0, "started": world.ticks, "expires": world.ticks + WorldEconomy.DAY_TICKS * 4}
	WorldEconomy.set_task(world, best, WorldEconomy.task("teach", Vector2i(home.x, home.y)))
	best.task.dependent = int(student.id)
	best.task.skill = best_skill
	best.job = "teacher"
	return true

static func student_step(world, student: Dictionary, home: Dictionary) -> bool:
	if student.lesson.is_empty(): return false
	var lesson: Dictionary = student.lesson
	var mentor := WorldLife.person(world, lesson.mentor)
	if not eligible(world, student, mentor, lesson.skill) or world.ticks > lesson.expires or mentor.task.get("kind", "") != "teach" or mentor.task.get("dependent", -1) != student.id:
		cancel_lesson(world, student)
		return false
	var target := Vector2i(mentor.task.x, mentor.task.y)
	if not WorldEconomy.navigation(world, home).parents.has(target) or world.fires.has(target):
		cancel_lesson(world, student)
		return false
	WorldEconomy.move(world, student, target, home)
	student.job = "researcher" if WorldLife.adult(world, student) else ("teen" if WorldLife.years(world, student) >= 13 else "child")
	student.energy = minf(100, student.energy + 0.5)
	return true

static func lesson_work(world, home: Dictionary) -> int:
	return 8 if not home.is_empty() and WorldSociety.active(world, home, "records") else LESSON_WORK

static func teach(world, mentor: Dictionary, home: Dictionary) -> void:
	var student := WorldLife.person(world, mentor.task.dependent)
	if student.is_empty() or student.lesson.get("mentor", -1) != mentor.id:
		WorldEconomy.set_task(world, mentor, {})
		return
	var lesson: Dictionary = student.lesson
	if not eligible(world, student, mentor, lesson.skill) or world.ticks > lesson.expires:
		cancel_lesson(world, student)
		return
	var target := Vector2i(mentor.task.x, mentor.task.y)
	if not WorldEconomy.navigation(world, home).parents.has(target) or world.fires.has(target):
		cancel_lesson(world, student)
		return
	if not WorldEconomy.move(world, mentor, target, home) or not near(mentor, student, 2): return
	lesson.work += 1
	mentor.task.work = lesson.work
	mentor.energy = maxf(0, mentor.energy - 0.5)
	var required_work := lesson_work(world, home)
	if lesson.work < required_work: return
	var skill: String = lesson.skill
	var limit := 120 if WorldLife.adult(world, student) else (80 if WorldLife.years(world, student) >= 13 else 30)
	var first_lesson: bool = student.trained_by.get(skill, -1) != mentor.id
	student.skills[skill] = mini(limit, mini(int(mentor.skills[skill]) - 10, int(student.skills[skill]) + 4 + int(student.traits.curiosity)))
	world.workforce.skill_changed(world, student, skill)
	student.trained_by[skill] = int(mentor.id)
	world.metrics.lessons += 1
	WorldSociety.taught(world, mentor, student)
	if required_work == 8: WorldSociety.use(world, home, "records", mentor)
	contact(world, mentor, student, 2)
	if first_lesson:
		world.log_event("Ученик ремесла", "%s учится у %s: %s." % [student.name, mentor.name, SKILLS[skill]])
	cancel_lesson(world, student)

static func tick(world) -> void:
	for member in world.people: tick_member(world, member)

static func tick_member(world, member: Dictionary) -> void:
	member.social_need = minf(100, member.social_need + (0.0625 if member.traits.sociability == 0 else (0.25 if member.traits.sociability == 2 else 0.125)))
	if not member.lesson.is_empty() and WorldLife.adult(world, member) and WorldEconomy.count(world, WorldEconomy.town(world, member.home), "school") == 0: cancel_lesson(world, member)


static func daily(world) -> void:
	for home in world.towns:
		var residents := WorldEconomy.members(world, home)
		for member in residents: daily_member(world, home, member)
		if world.ticks % WorldLife.YEAR == 0:
			for member in residents: fade_member(world, member)

static func daily_member(world, home: Dictionary, member: Dictionary) -> void:
	if WorldTravel.away(world, member.id): return
	var contacts := 0
	for other in world.population.nearby(world, Vector2i(member.x, member.y), 9, home.id, {"limit": 3, "after_id": member.id, "local": true}):
		if WorldTravel.away(world, other.id) or other.id <= member.id or not near(member, other): continue
		dispute(world,member,other,home)
		contact(world, member, other)
		contacts += 1
		if contacts >= 3: break
	if not member.lesson.is_empty(): return
	if WorldLife.years(world, member) in range(6, 18) or (WorldEconomy.count(world, home, "school") > 0 and member.cargo == 0 and member.task.get("kind", "") in ["", "rest", "visit"]): offer_lesson(world, member, home)

static func fade_member(world, member: Dictionary) -> void:
	for i in range(member.rivals.size()-1,-1,-1):
		var rival: Dictionary=member.rivals[i]
		if rival.id<member.id or world.ticks-int(rival.last_tick)<WorldLife.YEAR: continue
		var other:=WorldLife.person(world,rival.id)
		if other.is_empty(): continue
		var reverse:=rivalry(other,member.id)
		rival.resentment=maxi(0,int(rival.resentment)-8); reverse.resentment=rival.resentment
		if rival.resentment==0: member.rivals.remove_at(i); other.rivals.erase(reverse)
	for i in range(member.links.size() - 1, -1, -1):
		var link: Dictionary = member.links[i]
		if world.ticks - int(link.last_tick) < WorldLife.YEAR or link.id < member.id: continue
		var other := WorldLife.person(world, link.id)
		if other.is_empty(): continue
		var reverse := relation(other, member.id)
		link.bond = maxi(0, int(link.bond) - 2)
		reverse.bond = link.bond
		if link.bond == 0:
			member.links.remove_at(i)
			other.links.erase(reverse)


static func remove(world, member: Dictionary) -> void:
	cancel_lesson(world, member)
	for other in world.people:
		var rival:=rivalry(other,member.id)
		if not rival.is_empty(): other.rivals.erase(rival)
		if other.lesson.get("mentor", -1) == member.id: cancel_lesson(world, other)
		var link := relation(other, member.id)
		if not link.is_empty(): other.links.erase(link)
	for skill in SKILLS:
		if level(member, skill) < 3: continue
		var successors := false
		for other in world.people:
			if other.id != member.id and other.home == member.home and WorldLife.adult(world, other) and level(other, skill) >= 2: successors = true
		if not successors: world.log_event("Утрата мастера", "%s: %s осталось без опытного наставника." % [member.name, SKILLS[skill]])

static func describe(world, member: Dictionary) -> String:
	var text := "\n\nНавыки"
	var levels := ["Новичок", "Практик", "Опытный", "Мастер"]
	for skill in SKILLS:
		text += "\n%s: %s · %d" % [SKILLS[skill], levels[level(member, skill)], member.skills[skill]]
		if member.trained_by.has(skill): text += " · учитель " + WorldLife.label(world, member.trained_by[skill])
	var friends: Array[String] = []
	for link in member.links:
		if link.bond >= FRIEND: friends.append(WorldLife.label(world, link.id))
	text += "\n\nДрузья: " + (", ".join(friends) if not friends.is_empty() else "знакомится с соседями")
	var traits: Array[String] = []
	if member.traits.sociability == 2: traits.append("общительный")
	if member.traits.sociability == 0: traits.append("сдержанный")
	if member.traits.diligence == 2: traits.append("усердный")
	if member.traits.curiosity == 2: traits.append("любознательный")
	if not traits.is_empty(): text += "\n" + ", ".join(traits)
	for rival in member.rivals: text+="\nРазлад: %s · %d/100" % [WorldLife.label(world,rival.id),rival.resentment]
	if not member.lesson.is_empty(): text += "\nУчится: %s\nНаставник: %s · %d/%d" % [SKILLS[member.lesson.skill], WorldLife.label(world, member.lesson.mentor), member.lesson.work, lesson_work(world, WorldEconomy.town(world, member.home))]
	if member.task.get("kind", "") == "teach": text += "\nУченик: " + WorldLife.label(world, member.task.dependent)
	return text

static func summary(world, home: Dictionary) -> String:
	var text := "\nРемёсла общины"
	for skill in SKILLS:
		var experienced := 0
		var students := 0
		for member in WorldEconomy.members(world, home):
			if WorldLife.adult(world, member) and level(member, skill) >= 2: experienced += 1
			if not WorldLife.adult(world, member) and member.skills[skill] > 0: students += 1
		text += "\n%s: опытных %d · учеников %d" % [SKILLS[skill], experienced, students]
	return text

static func restore(world) -> bool:
	for record in world.ancestry_archive:
		if not record.get("skills") is Dictionary or record.skills.size() != SKILLS.size(): return false
		for skill in SKILLS:
			if not WorldState._integer(record.skills.get(skill)) or record.skills[skill] < 0 or record.skills[skill] > MAX_XP: return false
			record.skills[skill] = int(record.skills[skill])
	for member in world.people:
		if not member.get("skills") is Dictionary or member.skills.size() != SKILLS.size(): return false
		for skill in SKILLS:
			if not WorldState._integer(member.skills.get(skill)) or member.skills[skill] < 0 or member.skills[skill] > MAX_XP: return false
			member.skills[skill] = int(member.skills[skill])
		if not member.get("traits") is Dictionary or member.traits.size() != TRAITS.size(): return false
		for trait_key in TRAITS:
			if not WorldState._integer(member.traits.get(trait_key)) or member.traits[trait_key] < 0 or member.traits[trait_key] > 2: return false
			member.traits[trait_key] = int(member.traits[trait_key])
		if not (member.get("social_need") is int or member.get("social_need") is float) or not is_finite(float(member.social_need)) or member.social_need < 0 or member.social_need > 100: return false
		member.social_need = float(member.social_need)
		if not member.get("links") is Array or member.links.size() > MAX_LINKS: return false
		var used := {}
		for link in member.links:
			if not link is Dictionary: return false
			for key in ["id", "bond", "last_tick"]:
				if not WorldState._integer(link.get(key)): return false
				link[key] = int(link[key])
			if link.id == member.id or used.has(link.id) or WorldLife.person(world, link.id).is_empty() or link.bond < 1 or link.bond > 100 or link.last_tick < 0 or link.last_tick > world.ticks: return false
			used[link.id] = true
		if not member.get("trained_by") is Dictionary or member.trained_by.size() > SKILLS.size(): return false
		for skill in member.trained_by:
			var id: Variant = member.trained_by[skill]
			if not SKILLS.has(skill) or not WorldState._integer(id) or id <= 0 or id >= world.next_id or id == member.id: return false
			member.trained_by[skill] = int(id)
		if not member.get("lesson") is Dictionary: return false
		if not member.lesson.is_empty():
			var lesson: Dictionary = member.lesson
			if not SKILLS.has(lesson.get("skill")): return false
			for key in ["mentor", "work", "started", "expires"]:
				if not WorldState._integer(lesson.get(key)): return false
				lesson[key] = int(lesson[key])
			if WorldLife.years(world, member) < 6 or (WorldLife.adult(world, member) and WorldEconomy.count(world, WorldEconomy.town(world, member.home), "school") == 0) or lesson.work < 0 or lesson.work >= LESSON_WORK or lesson.started < 0 or lesson.started > world.ticks or lesson.expires != lesson.started + WorldEconomy.DAY_TICKS * 4: return false
	for member in world.people:
		for link in member.links:
			var reverse := relation(WorldLife.person(world, link.id), member.id)
			if reverse.is_empty() or reverse.bond != link.bond or reverse.last_tick != link.last_tick: return false
		if not member.get("rivals") is Array or member.rivals.size()>4: return false
		var rivals: Dictionary={}
		for rival in member.rivals:
			if not rival is Dictionary: return false
			for key in ["id","resentment","last_tick"]:
				if not WorldState._integer(rival.get(key)): return false
				rival[key]=int(rival[key])
			if rivals.has(rival.id) or rival.id==member.id or rival.resentment<=0 or rival.resentment>100 or rival.last_tick<0 or rival.last_tick>world.ticks: return false
			var other:=WorldLife.person(world,rival.id)
			if other.is_empty(): return false
			var reverse:=rivalry(other,member.id)
			if reverse.is_empty() or reverse.resentment!=rival.resentment or reverse.last_tick!=rival.last_tick: return false
			rivals[rival.id]=true
		if not member.lesson.is_empty():
			var mentor := WorldLife.person(world, member.lesson.mentor)
			if mentor.is_empty() or not WorldLife.adult(world, mentor) or mentor.home != member.home or mentor.task.get("kind", "") != "teach" or mentor.task.get("dependent", -1) != member.id or mentor.task.get("skill", "") != member.lesson.skill or mentor.task.work != member.lesson.work: return false
		if member.task.get("kind", "") == "teach":
			if not WorldState._integer(member.task.get("dependent")) or not SKILLS.has(member.task.get("skill")): return false
			member.task.dependent = int(member.task.dependent)
			var student := WorldLife.person(world, member.task.dependent)
			if not WorldLife.adult(world, member) or student.is_empty() or student.lesson.get("mentor", -1) != member.id: return false
	return true
