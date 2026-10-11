extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func fixture() -> WorldState:
	var world := WorldState.new()
	world.paint(Vector2i.ZERO, 20, WorldState.Terrain.GRASS)
	world.paint(Vector2i(4, 0), 2, WorldState.Terrain.FOREST)
	var home := {"id": world.next_id, "name": "Мастерская долина", "x": 0, "y": 0, "food": 48, "wood": 0, "level": 1}
	world.next_id += 1
	world.towns.append(home)
	WorldEconomy.add_building(world, home, "camp", Vector2i.ZERO, true)
	world.metrics.spawn_food += home.food
	for i in 3:
		world.add_person(Vector2i.ZERO if i < 2 else Vector2i(6, 0), false)
		world.people.back().home = home.id
		world.people.back().birth_tick = -40 * WorldLife.YEAR
		world.people.back().sex = "male"
	var child: Dictionary = world.people[2]
	child.birth_tick = -13 * WorldLife.YEAR
	child.parents = [int(world.people[0].id), int(world.people[1].id)]
	child.ancestors = child.parents.duplicate()
	child.generation = 2
	child.guardian = int(world.people[0].id)
	child.job = "teen"
	WorldLife.reconcile(world)
	WorldLife.join(world, child, WorldLife.household(world, world.people[0].household))
	world.people[0].skills.build = 120
	return world

func food_conserved(world: WorldState) -> bool:
	var stock := 0
	for home in world.towns: stock += home.food
	for family in world.households: stock += family.food
	for building in world.buildings: stock += building.stock
	for person in world.people:
		stock += person.rations
		if person.cargo_kind in ["food", "seed"]: stock += person.cargo
	for ship in world.voyages + world.journeys:
		stock += ship.food
		if ship.cargo_kind == "food": stock += ship.cargo
	var m := world.metrics
	return m.spawn_food + m.harvested_food + m.crop_food == stock + m.eaten_food + m.seed_food + m.spoiled_food + m.growth_food + m.lost_food + m.processed_food

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := fixture()
	var mentor: Dictionary = world.people[0]
	var peer: Dictionary = world.people[1]
	var child: Dictionary = world.people[2]
	check(child.skills.build == 0 and child.trained_by.is_empty(), "children do not inherit free skill from parents")
	var fixed := fixture()
	check(fixed.people[0].traits == mentor.traits, "personality is deterministic and independent of RNG draws")
	var random_state: int = world.rng.state
	for i in 12:
		world.ticks = i * WorldEconomy.DAY_TICKS
		WorldSocial.contact(world, mentor, peer)
	check(WorldSocial.closeness(mentor, peer) == 12 and WorldSocial.closeness(peer, mentor) == 12, "friendship takes repeated contacts and is reciprocal")
	check(world.rng.state == random_state, "social contacts do not perturb random event state")
	WorldSocial.contact(world, mentor, peer, 3)
	check(WorldSocial.closeness(mentor, peer) == 12, "repeat contact cannot farm trust within the same day")
	peer.x = 12
	world.ticks += 20
	WorldSocial.contact(world, mentor, peer)
	check(WorldSocial.closeness(mentor, peer) == 12, "distant residents cannot talk by teleportation")
	peer.x = 1
	peer.hunger = 40
	peer.rations = 0
	world.metrics.lost_food += 2
	WorldSocial.help(world, mentor)
	check(mentor.rations == 1 and peer.rations == 1 and world.metrics.helped_food == 1 and food_conserved(world), "friend shares one existing ration on contact")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null, "friendship and assistance serialize")
	world = fixture()
	mentor = world.people[0]
	child = world.people[2]
	check(WorldSocial.offer_lesson(world, child, world.towns[0]), "available master accepts an adolescent pupil")
	check(child.skills.build == 0 and mentor.task.kind == "teach" and child.task.is_empty(), "starting a lesson grants no skill and takes the mentor away from production")
	for i in 5: WorldSocial.teach(world, mentor, world.towns[0])
	check(child.lesson.work == 0 and child.skills.build == 0, "lesson cannot progress while pupil is distant")
	for i in 3: world.step()
	check(child.x < 6 and not child.lesson.is_empty() and child.skills.build == 0, "pupil physically walks to the meeting before learning")
	var restored := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(restored != null and JSON.stringify(restored.to_dict()) == JSON.stringify(world.to_dict()), "in-progress lesson preserves both participant references and work")
	for i in 40:
		world.step()
		if restored != null: restored.step()
	check(restored != null and JSON.stringify(restored.to_dict()) == JSON.stringify(world.to_dict()), "learning continues identically after reload")
	check(child.skills.build > 0 and child.skills.build <= 12 and child.trained_by.build == mentor.id and world.metrics.lessons > 0, "completed meetings transfer bounded skill and record the teacher")
	check(child.cargo == 0 and child.task.is_empty() and food_conserved(world), "apprentices consume food but produce no free resources")
	var acquired: int = child.skills.build
	world.remove_person(world.people.find(mentor), "проверка потери наставника")
	check(child.skills.build == acquired and child.lesson.is_empty(), "death cancels future teaching but preserves learned experience")
	check(WorldLife.label(world, child.trained_by.build).contains("†") and world.ancestry_archive[0].skills.build == 120, "teacher identity and craft remain in memory")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null and food_conserved(world), "teacher loss preserves save and food accounting")
	world = fixture()
	mentor = world.people[0]
	child = world.people[2]
	check(WorldSocial.offer_lesson(world, child, world.towns[0]), "new lesson can be arranged")
	WorldEconomy.set_task(world, mentor, WorldEconomy.task("rest", Vector2i.ZERO))
	check(child.lesson.is_empty(), "urgent reassignment cancels both sides immediately")
	check(WorldState.from_dict(world.to_dict()) != null, "interrupted lesson remains loadable on the same tick")
	WorldSocial.offer_lesson(world, child, world.towns[0])
	world.add_person(Vector2i.ZERO, false)
	var other_pupil: Dictionary = world.people.back()
	other_pupil.home = child.home
	other_pupil.birth_tick = -13 * WorldLife.YEAR
	WorldLife.reconcile(world)
	check(not WorldSocial.offer_lesson(world, other_pupil, world.towns[0]), "one mentor cannot double-book two pupils")
	mentor.hunger = 35
	WorldSocial.student_step(world, child, world.towns[0])
	check(child.lesson.is_empty() and mentor.task.is_empty(), "hunger interrupts teaching on both sides")
	mentor.hunger = 0
	child.birth_tick = -5 * WorldLife.YEAR
	check(not WorldSocial.offer_lesson(world, child, world.towns[0]), "infants are not apprentices")
	child.birth_tick = -13 * WorldLife.YEAR
	world.towns[0].food = 1
	check(not WorldSocial.offer_lesson(world, child, world.towns[0]), "food crisis takes priority over lessons")
	world = fixture()
	mentor = world.people[0]
	child = world.people[2]
	WorldSocial.offer_lesson(world, child, world.towns[0])
	world.paint(Vector2i.ZERO, 1, WorldState.Terrain.WATER)
	WorldSocial.student_step(world, child, WorldEconomy.town(world, child.home))
	check(child.lesson.is_empty() and WorldState.from_dict(world.to_dict()) != null, "destroyed meeting place cancels lesson and references safely")
	world = fixture()
	mentor = world.people[0]
	mentor.x = 4
	mentor.skills.wood = 0
	WorldEconomy.set_task(world, mentor, WorldEconomy.task("gather_wood", Vector2i(4, 0)))
	var novice_steps := 0
	while mentor.cargo == 0 and novice_steps < 10:
		WorldEconomy.execute(world, mentor, world.towns[0])
		world.ticks += 1
		novice_steps += 1
	check(mentor.skills.wood > 0 and mentor.cargo == 3 and world.wood_at(Vector2i(4, 0)) == 9, "real work grants practice and consumes finite timber")
	fixed = fixture()
	var expert: Dictionary = fixed.people[0]
	expert.x = 4
	expert.skills.wood = 120
	WorldEconomy.set_task(fixed, expert, WorldEconomy.task("gather_wood", Vector2i(4, 0)))
	var expert_steps := 0
	while expert.cargo == 0 and expert_steps < 10:
		WorldEconomy.execute(fixed, expert, fixed.towns[0])
		fixed.ticks += 1
		expert_steps += 1
	check(expert_steps < novice_steps and expert.cargo == 3 and fixed.wood_at(Vector2i(4, 0)) == 9, "master works faster without multiplying resource yield")
	var idle := fixture()
	var waiting: Dictionary = idle.people[0]
	var project := WorldEconomy.add_building(idle, idle.towns[0], "house", Vector2i(-4, 0))
	waiting.x = -4
	waiting.y = 0
	var before_xp: int = waiting.skills.build
	WorldEconomy.set_task(idle, waiting, WorldEconomy.task("build", Vector2i(-4, 0), project.id))
	WorldEconomy.execute(idle, waiting, idle.towns[0])
	check(waiting.skills.build == before_xp and project.work == 0, "waiting for missing material gives neither work nor practice")
	world = fixture()
	var legacy := world.to_dict()
	legacy.version = 4
	legacy.metrics.erase("lessons")
	legacy.metrics.erase("helped_food")
	for member in legacy.people:
		for key in ["skills", "traits", "links", "social_need", "lesson", "trained_by"]: member.erase(key)
	var upgraded := WorldState.from_dict(JSON.parse_string(JSON.stringify(legacy)))
	check(upgraded != null and upgraded.households == world.households and upgraded.people[2].birth_tick == child.birth_tick, "v4 migration preserves families and birth dates")
	if upgraded != null:
		check(upgraded.metrics.births == world.metrics.births and upgraded.metrics.deaths == world.metrics.deaths and upgraded.people[0].skills.build == 0, "v4 migration preserves demographics without granting unearned mastery")
		check(WorldState.from_dict(upgraded.to_dict()) != null, "migrated v4 saves as v5")
	world = fixture()
	mentor = world.people[0]
	peer = world.people[1]
	mentor.skills.wood = 120
	check(WorldSocial.preferred(world, mentor, world.towns[0], "wood") and not WorldSocial.preferred(world, peer, world.towns[0], "wood"), "settlement prefers an available specialist")
	world.towns[0].food = 1
	check(WorldSocial.preferred(world, peer, world.towns[0], "wood"), "urgent shortages do not wait for a specialist")
	world = fixture()
	mentor = world.people[0]
	peer = world.people[1]
	WorldSocial.contact(world, mentor, peer, 12)
	peer.x = 8
	check(WorldSocial.visit_target(world, mentor, world.towns[0]) == Vector2i(8, 0), "social need chooses a friend's reachable location")
	world.ticks = WorldLife.YEAR
	WorldSocial.daily(world)
	check(WorldSocial.closeness(mentor, peer) == 10 and WorldSocial.closeness(peer, mentor) == 10, "unvisited friendship decays symmetrically")
	for i in 12:
		world.add_person(Vector2i.ZERO, false)
		world.people.back().home = mentor.home
		WorldSocial.contact(world, mentor, world.people.back())
	check(mentor.links.size() == WorldSocial.MAX_LINKS, "social memory stays bounded in crowded settlements")
	WorldLife.reconcile(world)
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null, "bounded social graph roundtrips")
	world.remove_person(world.people.find(mentor), "проверка дружбы")
	var no_dead_links := true
	for member in world.people:
		if not WorldSocial.relation(member, mentor.id).is_empty(): no_dead_links = false
	check(no_dead_links and WorldState.from_dict(world.to_dict()) != null, "death removes live friendships without dangling references")
	for mutation in ["missing", "xp", "trait", "self", "one_sided", "lesson", "teacher", "need"]:
		var broken := fixture().to_dict()
		match mutation:
			"missing": broken.people[0].erase("skills")
			"xp": broken.people[0].skills.food = 241
			"trait": broken.people[0].traits.curiosity = 3
			"self": broken.people[0].links = [{"id": broken.people[0].id, "bond": 12, "last_tick": 0}]
			"one_sided": broken.people[0].links = [{"id": broken.people[1].id, "bond": 12, "last_tick": 0}]
			"lesson": broken.people[2].lesson = {"mentor": broken.people[0].id, "skill": "build", "work": 1, "started": 0, "expires": 80}
			"teacher": broken.people[2].trained_by = {"build": broken.people[2].id}
			"need": broken.people[0].social_need = 101
		check(WorldState.from_dict(broken) == null, "malformed social data rejected: " + mutation)
	print("Social: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
