class_name WorldVocation
extends RefCounted

const SKILLS := ["food", "wood", "build", "farm"]
const GOALS := ["master", "learn", "connect", "explore", "research", "teach"]
const NAMES := {"master": "Совершенствовать ремесло", "learn": "Освоить новое ремесло", "connect": "Проводить время с соседями", "explore": "Исследовать окрестности", "research": "Участвовать в открытии", "teach": "Передать опыт ученику"}
const CAREERS := {"food": "Добыча пищи", "wood": "Работа с древесиной", "build": "Строительство и ремесло", "farm": "Земледелие"}

static func defaults(world, member: Dictionary) -> void:
	var offset := posmod(hash(Vector2i(world.world_seed, member.id)), SKILLS.size())
	var skill: String = SKILLS[offset]
	var best := -1
	for candidate in SKILLS:
		var xp := int(member.skills[candidate])
		if xp > best or (xp == best and candidate == SKILLS[offset]): best = xp; skill = candidate
	member.vocation = {"skill": skill, "since": world.ticks, "goal": "master", "goal_skill": skill, "target": 40, "baseline": int(member.skills[skill]), "progress": 0, "completed": 0, "review": world.ticks + WorldEconomy.DAY_TICKS * 3 + posmod(int(member.id), WorldEconomy.DAY_TICKS), "attempt": -1}
	choose(world, member)

static func choose(world, member: Dictionary) -> void:
	var value: Dictionary = member.vocation
	var choices: Array[String] = ["master", "learn"]
	if int(member.traits.sociability) > 0: choices.append("connect")
	if int(member.traits.curiosity) == 2: choices.append("explore"); choices.append("research")
	if int(member.skills[value.skill]) >= 120 and int(member.traits.sociability) > 0: choices.append("teach")
	if int(member.skills[value.skill]) >= WorldSocial.MAX_XP: choices.erase("master")
	var pick := posmod(hash("%d:%d:%d:goal" % [world.world_seed, member.id, world.ticks / WorldEconomy.DAY_TICKS]), choices.size())
	value.goal = choices[pick]
	if not WorldLife.adult(world, member): value.goal = "learn"
	value.goal_skill = value.skill
	if value.goal == "learn":
		var lowest := WorldSocial.MAX_XP + 1
		var offset := posmod(hash(Vector2i(world.world_seed + world.ticks / WorldEconomy.DAY_TICKS, member.id)), SKILLS.size())
		for i in SKILLS.size():
			var skill: String = SKILLS[(i + offset) % SKILLS.size()]
			if int(member.skills[skill]) < lowest: lowest = int(member.skills[skill]); value.goal_skill = skill
	value.baseline = int(member.skills[value.goal_skill])
	value.progress = 0
	value.target = mini(40, WorldSocial.MAX_XP - int(value.baseline)) if value.goal in ["master", "learn"] else (3 if value.goal == "connect" else 1)
	value.target = maxi(1, int(value.target))
	if not WorldLife.adult(world, member): value.target = mini(20, int(value.target))
	value.attempt = -1
	value.review = world.ticks + WorldEconomy.DAY_TICKS * 3 + posmod(int(member.id), WorldEconomy.DAY_TICKS)

static func score(member: Dictionary, skill: String) -> int:
	var value: Dictionary = member.get("vocation", {})
	return (48 if value.get("skill", "") == skill else 0) + (20 if value.get("goal", "") == "learn" and value.get("goal_skill", "") == skill else 0)

static func lesson_rank(student: Dictionary, mentor: Dictionary, skill: String) -> int:
	var goal: Dictionary = student.get("vocation", {})
	return (12 if mentor.get("vocation", {}).get("goal", "") == "teach" else 0) + (8 if goal.get("goal", "") == "learn" and goal.get("goal_skill", "") == skill else 0)

static func progress(member: Dictionary) -> int:
	var value: Dictionary = member.vocation
	if value.goal in ["master", "learn"]: return clampi(int(member.skills[value.goal_skill]) - int(value.baseline), 0, int(value.target))
	return int(value.progress)

static func milestone(member: Dictionary, goal: String) -> void:
	if not member.has("vocation") or member.vocation.goal != goal: return
	member.vocation.progress = mini(int(member.vocation.target), int(member.vocation.progress) + 1)

static func review(world, member: Dictionary, home: Dictionary) -> void:
	if not member.has("vocation"): defaults(world, member)
	var value: Dictionary = member.vocation
	if world.ticks < int(value.review) or not WorldLife.adult(world, member): return
	if progress(member) >= int(value.target): value.completed = mini(1000000, int(value.completed) + 1)
	var nav := WorldEconomy.navigation(world, home)
	var available := {"food": not nav.food.is_empty() or not nav.coasts.is_empty(), "wood": not nav.wood.is_empty(), "build": true, "farm": WorldEconomy.count(world, home, "farm", false) > 0}
	var chosen: String = value.skill
	var strongest := -1
	for skill in SKILLS:
		if not available[skill]: continue
		var strength := int(member.skills[skill]) + (16 if skill == value.skill else 0)
		if strength > strongest: strongest = strength; chosen = skill
	if chosen != value.skill: value.skill = chosen; value.since = world.ticks
	choose(world, member)
	for skill in SKILLS: world.workforce.skill_changed(world, member, skill)

static func assign_goal(world, member: Dictionary, home: Dictionary) -> bool:
	if not WorldLife.adult(world, member) or WorldEconomy.food_days(world, home) < 10 or member.hunger >= 25 or member.energy < 40: return false
	var value: Dictionary = member.vocation
	if progress(member) >= int(value.target): return false
	var month: int = world.ticks / WorldEconomy.DAY_TICKS
	if int(value.attempt) == month: return false
	value.attempt = month
	if value.goal == "explore": return WorldExploration.assign(world, member, home)
	if value.goal == "research": return WorldSociety.research_assign(world, member, home)
	if value.goal == "connect" and member.social_need >= 20:
		WorldEconomy.set_task(world, member, WorldEconomy.task("visit", WorldSocial.visit_target(world, member, home)))
		return true
	return false

static func describe(member: Dictionary) -> String:
	if not member.has("vocation"): return ""
	var value: Dictionary = member.vocation
	return "\n\nПредпочтение: %s\nСтремление: %s · %d/%d\nДостигнуто целей: %d" % [CAREERS[value.skill], NAMES[value.goal], progress(member), value.target, value.completed]

static func restore(world, member: Dictionary) -> bool:
	if not member.has("vocation"): defaults(world, member); return true
	var value: Variant = member.vocation
	if not value is Dictionary or value.get("skill") not in SKILLS or value.get("goal_skill") not in SKILLS or value.get("goal") not in GOALS: return false
	for field in ["since", "target", "baseline", "progress", "completed", "review", "attempt"]:
		if not WorldState._integer(value.get(field)): return false
	if value.since < 0 or value.since > world.ticks or value.target < 1 or value.target > WorldSocial.MAX_XP or value.baseline < 0 or value.baseline > WorldSocial.MAX_XP or value.progress < 0 or value.progress > value.target: return false
	if value.completed < 0 or value.completed > 1000000 or value.review < 0 or value.review > world.ticks + WorldEconomy.DAY_TICKS * 4 or value.attempt < -1 or value.attempt > world.ticks / WorldEconomy.DAY_TICKS: return false
	for field in ["since", "target", "baseline", "progress", "completed", "review", "attempt"]: value[field] = int(value[field])
	return true
