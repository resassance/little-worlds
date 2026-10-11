extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func family_world() -> WorldState:
	var world := WorldState.new()
	world.paint(Vector2i.ZERO, 20, WorldState.Terrain.GRASS)
	world.paint(Vector2i(10, 0), 5, WorldState.Terrain.FOREST)
	var home := {"id": world.next_id, "name": "Долина поколений", "x": 0, "y": 0, "food": 40, "wood": 0, "level": 2}
	world.next_id += 1
	world.towns.append(home)
	WorldEconomy.add_building(world, home, "camp", Vector2i.ZERO, true)
	WorldEconomy.add_building(world, home, "house", Vector2i(4, 0), true)
	world.metrics.spawn_food += 40
	for i in 2:
		world.add_person(Vector2i.ZERO, false)
		world.people.back().home = home.id
		world.people.back().birth_tick = -20 * WorldLife.YEAR
	world.people[0].sex = "female"
	world.people[1].sex = "male"
	WorldLife.reconcile(world)
	WorldLife.make_pair(world, world.people[0], world.people[1])
	return world

func newborn(world: WorldState) -> Dictionary:
	var mother: Dictionary = world.people[0]
	var location := WorldLife.dwelling_cell(world, WorldLife.household(world, mother.household))
	mother.x = location.x
	mother.y = location.y
	mother.birth_due = world.ticks
	if not WorldLife.give_birth(world, mother): return {}
	return world.people.back()

func advance(world: WorldState, ticks: int) -> void:
	for i in ticks: world.step()

func food_conserved(world: WorldState) -> bool:
	var stored := 0
	for home in world.towns: stored += home.food
	for family in world.households: stored += family.food
	for building in world.buildings: stored += building.stock
	for member in world.people:
		stored += member.rations
		if member.cargo_kind in ["food", "seed"]: stored += member.cargo
	for ship in world.voyages + world.journeys:
		stored += ship.food
		if ship.cargo_kind == "food": stored += ship.cargo
	var m := world.metrics
	return m.spawn_food + m.harvested_food + m.crop_food == stored + m.eaten_food + m.seed_food + m.spoiled_food + m.growth_food + m.lost_food + m.processed_food

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := family_world()
	var mother: Dictionary = world.people[0]
	var father: Dictionary = world.people[1]
	check(WorldLife.years(world, mother) == 20 and WorldLife.adult(world, mother), "player-created settlers start as adults with birth dates")
	for boundary in [0, 6, 13, 18, 40, 60]:
		mother.birth_tick = -boundary * WorldLife.YEAR
		check(WorldLife.stage(world, mother) == [0, 6, 13, 18, 40, 60].find(boundary), "stage boundary at age %d" % boundary)
	mother.birth_tick = -20 * WorldLife.YEAR
	var original_stock: int = world.towns[0].food
	WorldLife.daily(world)
	check(mother.birth_due == WorldLife.YEAR * 3 / 4 and world.people.size() == 2, "birth has a persistent waiting period and does not instantly add an adult")
	check(world.towns[0].food == original_stock, "planning a birth does not purchase a child with stock")
	var awaiting := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(awaiting != null and JSON.stringify(awaiting.to_dict()) == JSON.stringify(world.to_dict()), "waiting birth, partnership and household roundtrip exactly")
	if awaiting != null:
		advance(world, 200)
		advance(awaiting, 200)
		check(JSON.stringify(world.to_dict()) == JSON.stringify(awaiting.to_dict()), "one waiting birth completes identically after reload")
		check(world.metrics.births == 1 and world.people.size() == 3, "exactly one child is born at the end of waiting")

	world = family_world()
	mother = world.people[0]
	father = world.people[1]
	var spawn_food_before: int = world.metrics.spawn_food
	var child := newborn(world)
	check(not child.is_empty(), "supported family can have a newborn")
	if child.is_empty(): quit(1); return
	check(WorldLife.years(world, child) == 0 and child.birth_tick == world.ticks and child.rations == 0 and child.cargo == 0, "newborn has age zero and no free food or cargo")
	check(child.parents == [mother.id, father.id] and child.guardian == mother.id and child.generation == 2 and child.home == mother.home, "newborn retains parents, guardian, generation and settlement")
	check(world.metrics.spawn_food == spawn_food_before and food_conserved(world), "birth preserves resource balance without the old growth fee")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null, "world is loadable immediately on the birth tick")
	var family := WorldLife.household(world, child.household)

	family.food = 3
	world.metrics.spawn_food += 7
	child.care_until = 0
	mother.cargo = 4
	mother.cargo_kind = "food"
	WorldLife.assign_care(world, mother, world.towns[0])
	for i in 3: WorldEconomy.execute(world, mother, world.towns[0])
	check(family.food == 4 and mother.cargo == 3 and food_conserved(world), "full household keeps excess care food in the basket without overflow or loss")
	check(WorldState.from_dict(world.to_dict()) != null, "overlapping care delivery remains loadable")
	world.metrics.lost_food += family.food + mother.cargo
	family.food = 0
	mother.cargo = 0
	mother.cargo_kind = ""
	child.hunger = 20
	child.care_until = 0
	var home: Dictionary = world.towns[0]
	var prior_stock: int = home.food
	mother.x = 0
	mother.y = 0
	WorldLife.assign_care(world, mother, home)
	WorldEconomy.execute(world, mother, home)
	check(home.food == prior_stock - 4 and mother.cargo == 4 and family.food == 0, "caregiver takes real food from camp into a basket")
	var in_transit := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(in_transit != null and in_transit.people[0].task.kind == "care" and in_transit.people[0].task.dependent == child.id, "care delivery and dependent survive saving in transit")
	for i in 30:
		WorldEconomy.execute(world, mother, home)
		if mother.task.is_empty(): break
	check(mother.cargo == 0 and family.food == 4 and child.care_until > world.ticks, "only contact delivers family food and renews care")
	check(food_conserved(world), "care delivery conserves family and common stocks")
	var eaten_before: int = world.metrics.eaten_food
	advance(world, 2)
	check(child.hunger < 20 and world.metrics.eaten_food > eaten_before and food_conserved(world), "child eats food supplied by adults")
	var production_before: int = world.metrics.harvested_wood + world.metrics.built_wood
	WorldLife.dependent_step(world, child, home)
	check(child.task.is_empty() and child.job == "child" and world.metrics.harvested_wood + world.metrics.built_wood == production_before, "infants perform no production tasks")
	child.birth_tick = world.ticks - 13 * WorldLife.YEAR
	child.care_until = world.ticks + 40
	WorldLife.dependent_step(world, child, home)
	check(child.job == "teen" and not WorldLife.adult(world, child) and WorldLife.hunger_rate(world, child) == 0.375, "teenagers have distinct consumption and remain dependent")
	child.birth_tick = world.ticks - 18 * WorldLife.YEAR
	WorldLife.reconcile(world)
	check(WorldLife.adult(world, child) and child.guardian == -1 and child.job == "settler", "adult child becomes an independent worker")
	child.birth_tick = world.ticks
	child.job = "child"
	child.guardian = mother.id
	world.remove_person(world.people.find(mother), "испытание потери опекуна")
	WorldLife.reconcile(world)
	check(child.guardian == father.id and child.parents.has(mother.id) and child.parents.has(father.id), "surviving parent takes care without losing original parenthood")
	check(world.ancestry_archive.size() == 1 and WorldLife.label(world, mother.id).contains(mother.name), "dead parent remains in family history")
	check(father.partner == -1 and father.birth_due == -1, "bereavement clears active partnership and waiting birth")
	check(food_conserved(world) and WorldState.from_dict(world.to_dict()) != null, "orphan care preserves resources and valid saves")
	world.add_person(Vector2i.ZERO, false)
	var volunteer: Dictionary = world.people.back()
	volunteer.home = home.id
	WorldLife.reconcile(world)
	world.remove_person(world.people.find(father), "испытание полной опеки")
	WorldLife.reconcile(world)
	check(child.guardian == volunteer.id and child.household == volunteer.household, "community caregiver adopts a child after both parents die")
	world.remove_person(world.people.find(volunteer), "испытание отсутствия взрослых")
	WorldLife.reconcile(world)
	child.hunger = 0
	world.metrics.spawn_food += 2 - int(child.rations)
	child.rations = 2
	child.health = 1
	child.care_until = 0
	advance(world, 12)
	check(world.people.is_empty(), "food alone cannot replace care for an unattended infant")
	check(world.ancestry_archive.size() == 4 and food_conserved(world), "death archives and abandoned food remain bounded and accounted")

	world = family_world()
	mother = world.people[0]
	father = world.people[1]
	mother.ancestors = [123]
	father.ancestors = [123]
	check(WorldLife.related(mother, father) and not WorldLife.partner_valid(world, mother, father), "shared ancestry prevents a related partnership")
	mother.ancestors = []
	father.ancestors = []
	mother.birth_tick = -17 * WorldLife.YEAR
	check(not WorldLife.birth_conditions(world, mother, true), "minor cannot become a parent")
	mother.birth_tick = -20 * WorldLife.YEAR
	world.towns[0].food = 1
	check(not WorldLife.birth_conditions(world, mother, true), "lack of reserves blocks a new birth")
	world.towns[0].food = 40
	mother.last_birth = 0
	check(not WorldLife.birth_conditions(world, mother, true), "family respects birth spacing")
	mother.last_birth = -2 * WorldLife.YEAR
	for i in WorldState.MAX_PEOPLE - world.people.size(): world.add_person(Vector2i.ZERO, false)
	var cap_food: int = world.towns[0].food
	check(not WorldLife.birth_conditions(world, mother, true) and world.towns[0].food == cap_food, "population cap prevents birth without removing supplies")

	world = family_world()
	child = newborn(world)
	var corrupted := world.to_dict()
	corrupted.people[2].birth_tick = world.ticks + 1
	check(WorldState.from_dict(corrupted) == null, "future birth date rejected")
	corrupted = world.to_dict()
	corrupted.people[2].guardian = child.id
	check(WorldState.from_dict(corrupted) == null, "child cannot be their own guardian")
	corrupted = world.to_dict()
	corrupted.people[2].parents = [child.id, world.people[0].id]
	check(WorldState.from_dict(corrupted) == null, "self-parenthood rejected")
	corrupted = world.to_dict()
	corrupted.households.append(corrupted.households[0].duplicate(true))
	check(WorldState.from_dict(corrupted) == null, "duplicate households rejected")
	corrupted = world.to_dict()
	corrupted.people[2].cargo = 1
	corrupted.people[2].cargo_kind = "wood"
	check(WorldState.from_dict(corrupted) == null, "production cargo on an infant rejected")
	corrupted = world.to_dict()
	corrupted.people[1].erase("ancestors")
	check(WorldState.from_dict(corrupted) == null, "missing related-person fields rejected without runtime errors")
	corrupted = world.to_dict()
	corrupted.people[1].partner = -1
	check(WorldState.from_dict(corrupted) == null, "one-sided partnership rejected")
	corrupted = world.to_dict()
	corrupted.households[0].food = 5
	check(WorldState.from_dict(corrupted) == null, "overfilled family pantry rejected")


	world.paint(Vector2i.ZERO, 1, WorldState.Terrain.WATER)
	check(WorldState.from_dict(world.to_dict()) != null, "camp removal keeps living families and saved references consistent")
	world = family_world()
	child = newborn(world)
	mother = world.people[0]
	father = world.people[1]
	for member in world.people: member.home = -1
	WorldLife.reconcile(world)
	child.hunger = 20
	child.care_until = 0
	WorldLife.dependent_step(world, child, {})
	check(child.care_until > world.ticks and child.rations == 1 and mother.rations == 1 and food_conserved(world), "unsettled caregiver shares a real ration and provides care on contact")
	check(WorldState.from_dict(world.to_dict()) != null, "unsettled family saves with consistent partnership and household")

	world = family_world()
	advance(world, 35)
	var legacy := world.to_dict()
	legacy.version = 3
	legacy.erase("households")
	legacy.erase("ancestry_archive")
	legacy.metrics.erase("births")
	legacy.metrics.erase("deaths")
	for member in legacy.people:
		for key in ["birth_tick", "sex", "parents", "ancestors", "generation", "guardian", "partner", "household", "courting", "bond", "birth_due", "last_birth", "care_until", "health"]: member.erase(key)
	var upgraded := WorldState.from_dict(JSON.parse_string(JSON.stringify(legacy)))
	check(upgraded != null and upgraded.towns == world.towns and upgraded.buildings == world.buildings, "v3 migration retains real stocks and buildings")
	if upgraded != null:
		var preserved := true
		for i in world.people.size():
			for key in ["id", "name", "age", "task", "job", "cargo", "cargo_kind", "rations", "energy", "x", "y", "hunger"]:
				if upgraded.people[i][key] != world.people[i][key]: preserved = false
		check(preserved and WorldLife.adult(upgraded, upgraded.people[0]), "migration assigns adult age once while retaining lived ticks and active work")
		check(WorldState.from_dict(upgraded.to_dict()) != null, "upgraded v3 saves again as v4")
	print("Life: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
