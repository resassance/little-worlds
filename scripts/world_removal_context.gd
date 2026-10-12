class_name WorldRemovalContext
extends RefCounted

var world
var cursor := 0
var references: Dictionary = {}
var skills: Dictionary = {}
var finished := false

func _init(value) -> void:
	world = value

func unit() -> void:
	if finished: return
	if cursor >= world.people.size(): finished = true; return
	var member: Dictionary = world.people[cursor]; cursor += 1
	var targets := {}
	for id in [member.partner,member.courting,member.guardian,member.task.get("dependent",-1),member.lesson.get("mentor",-1)]:
		if int(id) > 0: targets[int(id)] = true
	for id in targets:
		if not references.has(id): references[id] = []
		references[id].append(member)
	if WorldLife.adult(world,member):
		if not skills.has(member.home): skills[member.home] = {}
		for skill in WorldSocial.SKILLS:
			if WorldSocial.level(member,skill) >= 2: skills[member.home][skill] = int(skills[member.home].get(skill,0))+1

func removed(member: Dictionary) -> void:
	if not WorldLife.adult(world,member): return
	var counts: Dictionary = skills.get(member.home,{})
	for skill in WorldSocial.SKILLS:
		if WorldSocial.level(member,skill) >= 2: counts[skill] = maxi(0,int(counts.get(skill,0))-1)
