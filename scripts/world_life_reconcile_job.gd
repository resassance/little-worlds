class_name WorldLifeReconcileJob
extends RefCounted

var world
var cursor := 0
var phase := 0
var child_cursor := -1
var parent: Dictionary = {}
var mate: Dictionary = {}
var family: Dictionary = {}
var finished := false

func _init(value) -> void:
	world = value
	world.life_dirty = false

func unit() -> void:
	if finished: return
	match phase:
		0:
			if cursor < world.people.size():
				WorldLife.reconcile_member(world, world.people[cursor]); cursor += 1
			else: phase = 1; cursor = 0
		1:
			if child_cursor >= 0:
				if child_cursor < world.people.size():
					var child: Dictionary = world.people[child_cursor]; child_cursor += 1
					if child.guardian in [parent.id, mate.id] and child.home == parent.home and not WorldLife.adult(world, child): WorldLife.join(world, child, family)
				else: child_cursor = -1
			elif cursor < world.people.size():
				parent = world.people[cursor]; cursor += 1
				mate = WorldLife.person(world, parent.partner)
				if mate.is_empty() or mate.home != parent.home or mate.household == parent.household: return
				family = WorldLife.household(world, parent.household)
				if family.is_empty(): return
				WorldLife.join(world, mate, family)
				child_cursor = 0
			else: phase = 2; cursor = world.households.size() - 1
		2:
			if cursor >= 0:
				var value: Dictionary = world.households[cursor]
				if value.members.is_empty():
					world.metrics.lost_food += value.food
					world.household_index.erase(value.id)
					world.households.remove_at(cursor)
				cursor -= 1
			else:
				world.population.shelter_load.clear()
				phase = 3; cursor = 0
		3:
			if cursor < world.households.size():
				var value: Dictionary = world.households[cursor]; cursor += 1
				if value.dwelling != -1: world.population.shelter_load[value.dwelling] = int(world.population.shelter_load.get(value.dwelling, 0)) + value.members.size()
			else:
				world.population.settling = true
				phase = 4; cursor = 0
		4:
			if cursor < world.households.size():
				WorldLife.settle(world, world.households[cursor]); cursor += 1
			else:
				world.population.end_settlement()
				world.population.ready = false
				phase = 5; cursor = 0
		5:
			if cursor < world.people.size():
				WorldLife.reconcile_links(world, world.people[cursor]); cursor += 1
			else: finished = true
