class_name WorldPersonRemovalJob
extends RefCounted

var world
var member: Dictionary
var cause: String
var phase := 0
var cursor := 0
var successors: Dictionary = {}
var finished := false
var masters: Array[String] = []
var student_id := -1
var context: WorldRemovalContext
var related: Array = []

func _init(value, person: Dictionary, reason: String) -> void:
	world = value; member = person; cause = reason
	for skill in WorldSocial.SKILLS:
		if WorldSocial.level(member,skill) >= 3: masters.append(skill)
	if member.task.get("kind","") == "teach": student_id = int(member.task.get("dependent",-1))

func unit() -> void:
	if finished: return
	match phase:
		0:
			world.heritage.lost(member.id)
			WorldTravel.death(world,member.id); WorldMaritime.death(world,member.id)
			WorldEconomy.lose_cargo(world,member); WorldSocial.cancel_lesson(world,member)
			for connection in member.links:
				var other := WorldLife.person(world,connection.id)
				if not other.is_empty():
					var reverse := WorldSocial.relation(other,member.id)
					if not reverse.is_empty(): other.links.erase(reverse)
			for connection in member.rivals:
				var other := WorldLife.person(world,connection.id)
				if not other.is_empty():
					var reverse := WorldSocial.rivalry(other,member.id)
					if not reverse.is_empty(): other.rivals.erase(reverse)
			var student := WorldLife.person(world,student_id)
			if not student.is_empty() and student.lesson.get("mentor",-1) == member.id: WorldSocial.cancel_lesson(world,student)
			if context != null:
				context.removed(member)
				related = context.references.get(member.id,[])
				for skill in masters:
					if int(context.skills.get(member.home,{}).get(skill,0)) > 0: successors[skill] = true
			phase = 2 if masters.is_empty() or context != null else 1; cursor = 0
		1:
			for i in 32:
				if cursor >= world.people.size(): phase = 2; return
				var other: Dictionary = world.people[cursor]; cursor += 1
				if other.id != member.id and other.home == member.home and WorldLife.adult(world,other):
					for skill in masters:
						if WorldSocial.level(other,skill) >= 2: successors[skill] = true
		2:
			for skill in masters:
				if not successors.has(skill): world.log_event("Утрата мастера","%s: %s осталось без опытного наставника." % [member.name,WorldSocial.SKILLS[skill]])
			var record := {"id":member.id,"name":member.name,"birth_tick":member.birth_tick,"death_tick":world.ticks,"parents":member.parents.duplicate(),"generation":member.generation,"cause":cause,"skills":member.skills.duplicate()}
			world.ancestry_archive.append(record)
			if world.ancestry_archive.size() > WorldLife.MAX_ARCHIVE: world.ancestry_archive.pop_front()
			world.metrics.deaths += 1
			phase = 3; cursor = 0
		3:
			for i in 32:
				if cursor >= (world.people.size() if context == null else related.size()):
					var family := WorldLife.household(world,member.household)
					if not family.is_empty(): family.members.erase(member.id)
					phase = 4; cursor = world.households.size()-1; return
				var other: Dictionary = world.people[cursor] if context == null else related[cursor]; cursor += 1
				if not world.person_index.has(other.id): continue
				if other.partner == member.id: other.partner = -1; other.birth_due = -1
				if other.courting == member.id: other.courting = -1; other.bond = 0
				if other.guardian == member.id: other.guardian = -1
				if other.task.get("dependent",-1) == member.id: WorldEconomy.set_task(world,other,{})
		4:
			if context != null:
				var family := WorldLife.household(world,member.household)
				if not family.is_empty() and family.members.is_empty():
					world.metrics.lost_food += family.food; world.household_index.erase(family.id); world.households.erase(family)
				phase = 5; return
			for i in 32:
				if cursor < 0: phase = 5; return
				var family: Dictionary = world.households[cursor]; cursor -= 1
				if family.members.is_empty():
					world.metrics.lost_food += family.food; world.household_index.erase(family.id); world.households.erase(family)
		5:
			world.heritage.resident_lost(world,member,cause)
			world.person_index.erase(member.id); world.people.erase(member)
			world.population.ready = false; world.workforce.plans.clear(); world.workforce.contributions.clear()
			WorldSociety.invalidate(world); world.population_dirty = true; world.life_dirty = true
			world.log_event("Потеря жителя","%s: %s." % [member.name,cause])
			finished = true
