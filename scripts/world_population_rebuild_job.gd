class_name WorldPopulationRebuildJob
extends RefCounted

var world
var cursor := 0
var previous_id := -1
var finished := false

func _init(value) -> void:
	world = value
	world.population.ready = false
	world.population.cells.clear(); world.population.locations.clear()
	world.population.order.clear(); world.population.dependents.clear()
	world.population.monotonic_ids = true

func unit() -> void:
	if finished: return
	if cursor >= world.people.size():
		world.population.ready = true
		finished = true
		return
	var member: Dictionary = world.people[cursor]
	if member.id <= previous_id: world.population.monotonic_ids = false
	previous_id = int(member.id)
	var key := WorldPopulation.bucket(Vector2i(member.x, member.y))
	if not world.population.cells.has(key): world.population.cells[key] = []
	world.population.cells[key].append(int(member.id))
	world.population.locations[member.id] = key
	world.population.order[member.id] = cursor
	if member.guardian != -1:
		if not world.population.dependents.has(member.guardian): world.population.dependents[member.guardian] = []
		world.population.dependents[member.guardian].append(int(member.id))
	cursor += 1
