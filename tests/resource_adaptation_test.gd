extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func settlement(sand: bool = false, population: int = 3, food: int = 40) -> WorldState:
	var world := WorldState.new()
	world.paint(Vector2i.ZERO, 4 if sand else 36, WorldState.Terrain.SAND if sand else WorldState.Terrain.GRASS)
	var home := {"id": world.next_id, "name": "Берег", "x": 0, "y": 0, "food": food, "wood": 0, "level": 1}
	world.next_id += 1
	world.towns.append(home)
	WorldEconomy.add_building(world, home, "camp", Vector2i.ZERO, true)
	world.metrics.spawn_food += food
	for i in population:
		world.add_person(Vector2i(i % 2, i / 2), false)
		world.people.back().home = home.id
	WorldLife.reconcile(world)
	WorldSociety.ensure_town(world, home)
	WorldCivilization.ensure(world, home)
	return world

func copy(world: WorldState) -> WorldState:
	return WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))

func finish_task(world: WorldState, person: Dictionary, maximum: int = 160) -> void:
	for i in maximum:
		if person.task.is_empty(): return
		world.ticks += 1
		WorldEconomy.execute(world, person, WorldEconomy.town(world, person.home))
	check(false, "Task did not finish")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := settlement(true, 3, 0)
	var home: Dictionary = world.towns[0]
	var person: Dictionary = world.people[0]
	WorldEconomy.assign(world, person, home)
	check(person.task.get("kind") == "fish" and person.task.get("basic", false), "A bare coast provides a real basic fishing job without carpentry")
	check(not WorldSociety.mastered(world, home, "carpentry"), "Basic fishing does not grant a technology")
	check(copy(world) != null, "Basic fishing saves during the walk")
	finish_task(world, person)
	check(person.cargo == 1 and person.cargo_kind == "food" and WorldAudit.conserved(world), "Basic fishing produces a small conserved catch")
	WorldEconomy.assign(world, person, home)
	finish_task(world, person)
	check(home.food == 1 and WorldAudit.conserved(world), "The catch is physically delivered to camp")
	for i in 120: world.step()
	check(world.people.size() == 3 and WorldAudit.conserved(world), "A woodless and rockless coast sustains its inhabitants")
	world = WorldState.new()
	world.paint(Vector2i.ZERO, 4, WorldState.Terrain.SAND)
	world.add_person(Vector2i.ZERO, false)
	for i in 200: world.step()
	check(world.people.size() == 1 and world.towns.is_empty() and world.metrics.harvested_food > 0 and WorldAudit.conserved(world), "A lone resident can fish and survive before founding a settlement")
	loaded_save_test(world)

	world = settlement()
	home = world.towns[0]
	person = world.people[0]
	world.paint(Vector2i(28, 0), 1, WorldState.Terrain.FOREST)
	check(not world.workforce.has_resource(world, home, "wood"), "The distant forest starts outside the known working area")
	check(WorldExploration.assign(world, person, home), "A timber shortage starts a prepared local expedition")
	check(not WorldExploration.assign(world, world.people[1], home), "The community assigns one explorer at a time")
	check(person.task.phase == "outbound" and WorldExploration.radius(home) == WorldEconomy.RANGE, "Departure does not instantly reveal a larger area")
	var loaded := copy(world)
	check(loaded != null, "An outbound expedition saves and restores")
	if loaded != null:
		for i in 12:
			world.step()
			var sliced := WorldStepJob.new(loaded)
			while not sliced.finished: sliced.advance(200)
		check(JSON.stringify(world.to_dict()) == JSON.stringify(loaded.to_dict()), "Full and sliced steps continue an expedition identically after loading")
	for i in 160:
		world.step()
		if WorldExploration.radius(home) > WorldEconomy.RANGE: break
	check(WorldExploration.radius(home) == 32, "Returned information expands the search area at the next navigation phase")
	check(world.workforce.has_resource(world, home, "wood"), "The expedition makes the distant real forest available")
	check(WorldAudit.conserved(world), "Exploration and provisions preserve resource balances")
	var gathered := false
	for i in 180:
		world.step()
		if world.metrics.harvested_wood > 0:
			gathered = true
			break
	check(gathered, "The discovery leads to real timber extraction")
	check(copy(world) != null, "The expanded working area roundtrips")

	world = settlement(true, 1, 10)
	home = world.towns[0]
	person = world.people[0]
	check(not WorldExploration.assign(world, person, home) and home.survey.exhausted, "An enclosed small island records that no landward frontier exists")
	var history_size := world.history.size()
	for i in 20: check(not WorldExploration.assign(world, person, home), "A failed search is not repeated without a change")
	check(world.history.size() == history_size, "A failed search does not spam the history")
	loaded = copy(world)
	check(loaded != null, "Negative search results save")
	if loaded != null:
		world.step(); loaded.step()
		check(JSON.stringify(world.to_dict()) == JSON.stringify(loaded.to_dict()), "Loading does not invalidate a remembered failed search")
	world.paint(Vector2i(20, 0), 22, WorldState.Terrain.SAND)
	loaded = copy(world)
	check(loaded != null and home.survey.dirty, "A changed surveyed area saves its pending update")
	if loaded != null:
		world.step(); loaded.step()
		check(JSON.stringify(world.to_dict()) == JSON.stringify(loaded.to_dict()), "A changed surveyed area is reconsidered identically after loading")
	WorldExploration.prepare(world, home)
	WorldEconomy.set_task(world, person, {})
	person.hunger = 0; person.energy = 100
	check(WorldExploration.assign(world, person, home), "New reachable land allows another search")

	world = settlement()
	home = world.towns[0]
	person = world.people[0]
	check(WorldExploration.assign(world, person, home), "A new timber expedition starts")
	var invalid := world.to_dict()
	invalid.towns[0].survey.radius = 1000000
	check(WorldState.from_dict(invalid) == null, "An unbounded saved search area is rejected")
	invalid = world.to_dict()
	invalid.people[0].task.phase = "teleport"
	check(WorldState.from_dict(invalid) == null, "An invalid saved expedition phase is rejected")
	invalid = world.to_dict()
	invalid.people[0].task.building = -1
	check(WorldState.from_dict(invalid) == null, "An expedition cannot belong to an unrelated camp")
	invalid = world.to_dict()
	invalid.towns[0].survey.pending_radius = 33
	check(WorldState.from_dict(invalid) == null, "Invalid pending exploration bounds are rejected")
	person.energy = 5
	WorldEconomy.execute(world, person, home)
	check(person.task.is_empty() or person.task.get("phase") == "returning", "An exhausted explorer turns back")

	world = settlement()
	home = world.towns[0]
	person = world.people[0]
	WorldEconomy.set_task(world, person, WorldEconomy.task("gather_food", Vector2i(12, 0)))
	world._set_food(Vector2i(12, 0), 0)
	WorldEconomy.execute(world, person, home)
	check(person.task.is_empty() and person.x == 0, "An exhausted source cancels the assignment before a pointless walk")
	var legacy := world.to_dict()
	legacy.version = 8
	check(WorldState.from_dict(legacy) != null, "Previous v8 worlds load into the new simulation")
	world.add_person(Vector2i(2, 2), false)
	loaded = copy(world)
	check(loaded != null, "A newly placed resident saves before the next tick")
	if loaded != null:
		world.step(); loaded.step()
		check(JSON.stringify(world.to_dict()) == JSON.stringify(loaded.to_dict()), "New residents form households identically after loading")
	print("Resource adaptation: ", "passed" if failures == 0 else "failed")
	quit(1 if failures else 0)

func loaded_save_test(world: WorldState) -> void:
	var loaded := copy(world)
	check(loaded != null, "An independent resident saves during survival")
	if loaded == null: return
	for i in 25:
		world.step(); loaded.step()
	check(JSON.stringify(world.to_dict()) == JSON.stringify(loaded.to_dict()), "Independent survival continues identically after loading")
