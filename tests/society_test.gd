extends SceneTree

var checks := 0
var failures := 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func fixture(experienced: bool = true) -> WorldState:
	var w := WorldState.new()
	w.paint(Vector2i.ZERO, 24, WorldState.Terrain.GRASS)
	w.paint(Vector2i(10, 0), 3, WorldState.Terrain.FOREST)
	var h := {"id": w.next_id, "name": "Долина знаний", "x": 0, "y": 0, "food": 48, "wood": 24, "level": 3}
	w.next_id += 1
	w.towns.append(h)
	w.metrics.spawn_food += 48
	w.metrics.harvested_wood += 24
	for spec in [["camp", Vector2i.ZERO], ["house", Vector2i(4, 4)], ["farm", Vector2i(-7, 4)], ["store", Vector2i(-7, -7)]]:
		var b := WorldEconomy.add_building(w, h, spec[0], spec[1], true)
		w.metrics.harvested_wood += WorldEconomy.COST[b.kind]
		w.metrics.built_wood += WorldEconomy.COST[b.kind]
	for i in 3:
		w.add_person(Vector2i(i, 0), false)
		w.people.back().home = h.id
		w.people.back().birth_tick = -25 * WorldLife.YEAR
		w.people.back().sex = "male"
		if experienced:
			for skill in WorldSocial.SKILLS: w.people.back().skills[skill] = 80
	WorldLife.reconcile(w)
	return w

func master(w: WorldState, key: String) -> void:
	var state: Dictionary = w.societies[0].tech[key]
	state.known = true
	state.mastered = true
	state.progress = WorldSociety.TECH[key].work
	state.discovered_tick = w.ticks
	WorldSociety.invalidate(w)

func ledger(w: WorldState) -> bool:
	var food := 0
	var wood := 0
	for home in w.towns:
		food += home.food
		wood += home.wood
	for family in w.households: food += family.food
	for b in w.buildings:
		food += b.stock
		if not b.ready: wood += b.delivered
	for p in w.people:
		food += p.rations
		if p.cargo_kind in ["food", "seed"]: food += p.cargo
		if p.cargo_kind == "wood": wood += p.cargo
	for ship in w.voyages + w.journeys:
		food += ship.food
		if ship.cargo_kind == "food": food += ship.cargo
		if ship.cargo_kind == "wood": wood += ship.cargo
	var m := w.metrics
	return m.spawn_food + m.harvested_food + m.crop_food == food + m.eaten_food + m.seed_food + m.spoiled_food + m.growth_food + m.lost_food + m.processed_food and m.harvested_wood == wood + m.built_wood + m.growth_wood + m.lost_wood + m.processed_wood

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var w := fixture(false)
	var h: Dictionary = w.towns[0]
	var s: Dictionary = w.societies[0]
	w.ticks = WorldLife.YEAR * 100
	for i in 20: WorldSociety.daily(w)
	check(s.era == 0 and not s.tech.carpentry.known and not s.tech.rotation.mastered, "calendar and ready buildings do not automatically give an era or technology")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(w.to_dict()))) != null, "new society roundtrips")
	w = fixture()
	h = w.towns[0]
	s = w.societies[0]
	for i in 60: WorldSociety.practice(w, w.people[0], "food")
	WorldSociety.daily(w)
	check(s.tech.preservation.known and not s.tech.preservation.mastered and s.project == "preservation", "local work suggests an idea before mastering it")
	var worker: Dictionary = w.people[0]
	worker.x = 8
	check(WorldSociety.research_assign(w, worker, h), "experienced available worker accepts a research task")
	var stock: int = h.food
	WorldEconomy.execute(w, worker, h)
	check(worker.x == 7 and s.tech.preservation.progress == 0 and h.food == stock, "researcher travels before working and no stock buys an instant unlock")
	while worker.x > 0: WorldEconomy.execute(w, worker, h)
	for i in 12:
		w.ticks += 1
		WorldEconomy.execute(w, worker, h)
	check(s.tech.preservation.progress > 0 and not s.tech.preservation.mastered, "research consumes actual working steps")
	var paused := WorldState.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	check(paused != null and JSON.stringify(paused.to_dict()) == JSON.stringify(w.to_dict()), "mid-research roundtrip preserves society, worker and progress")
	for i in 70:
		w.step()
		if paused != null: paused.step()
	check(paused != null and JSON.stringify(paused.to_dict()) == JSON.stringify(w.to_dict()), "research continues identically after loading")
	check(s.tech.preservation.mastered and worker.ideas.has("preservation") and w.metrics.discoveries >= 1, "completed research creates local mastery and a living carrier")
	check(ledger(w), "research and interrupted production conserve all resources")
	w = fixture()
	h = w.towns[0]
	s = w.societies[0]
	s.tech.carpentry.known = true
	s.project = "carpentry"
	worker = w.people[0]
	WorldSociety.research_assign(w, worker, h)
	check(not WorldSociety.research_assign(w, w.people[1], h), "one local research project cannot book two workers")
	for i in 5: WorldEconomy.execute(w, worker, h)
	var progress: int = s.tech.carpentry.progress
	h.food = 0
	WorldEconomy.execute(w, worker, h)
	check(worker.task.is_empty() and s.worker == -1 and s.tech.carpentry.progress == progress, "food crisis stops research and preserves invested work")
	h.food = 48
	w.people[1].skills.build = 0
	w.people[2].skills.build = 0
	w.people[0].skills.build = 0
	WorldSociety.invalidate(w)
	check(not WorldSociety.research_assign(w, worker, h) and WorldSociety.reason(w, h, "carpentry").contains("специалист"), "idea alone cannot replace a missing specialist")
	w = fixture()
	h = w.towns[0]
	master(w, "rotation")
	var farm := WorldEconomy.building(w, w.buildings[2].id)
	farm.planted = true
	farm.growth = 49
	w.step()
	check(farm.stock == 24 and not farm.planted and w.metrics.crop_food == 24, "applied rotation finishes at 50 steps and records 24 physical food")
	check(ledger(w) and WorldState.from_dict(JSON.parse_string(JSON.stringify(w.to_dict()))) != null, "improved crop conserves food and loads")
	var baseline := fixture()
	var baseline_farm: Dictionary = baseline.buildings[2]
	baseline_farm.planted = true
	baseline_farm.growth = 49
	baseline.step()
	check(baseline_farm.stock == 0 and baseline_farm.growth == 50, "untrained settlement keeps the basic crop cycle")
	w = fixture()
	h = w.towns[0]
	master(w, "preservation")
	w.metrics.spawn_food += 112
	h.food = 160
	w.ticks = 79
	w.step()
	check(w.metrics.spoiled_food == 0 and w.societies[0].tech.preservation.used > 0 and ledger(w), "preservation reduces spoilage using existing storage without adding food")
	baseline = fixture()
	baseline.metrics.spawn_food += 112
	baseline.towns[0].food = 160
	baseline.ticks = 79
	baseline.step()
	check(baseline.metrics.spoiled_food == 1 and ledger(baseline), "basic store has higher spoilage")
	w = fixture()
	h = w.towns[0]
	master(w, "carpentry")
	worker = w.people[0]
	worker.x = 10
	worker.y = 0
	w.ticks = 4 - int(worker.id) % 4
	WorldEconomy.set_task(w, worker, WorldEconomy.task("gather_wood", Vector2i(10, 0)))
	WorldEconomy.execute(w, worker, h)
	check(worker.task.work >= 2 and w.societies[0].tech.carpentry.used == 1, "local carpentry contributes work on site")
	check(worker.cargo == 0 and w.wood_at(Vector2i(10, 0)) == 12, "technology gives neither instant timber nor excess resource")
	w = fixture()
	h = w.towns[0]
	s = w.societies[0]
	master(w, "carpentry")
	master(w, "preservation")
	for p in w.people:
		p.skills.wood = 0
		p.skills.build = 0
	WorldSociety.invalidate(w)
	check(not WorldSociety.active(w, h, "carpentry") and s.tech.carpentry.mastered, "loss of craftspeople stops benefits while retaining known technology")
	w.people[1].skills.wood = 40
	w.people[1].skills.build = 40
	WorldSociety.invalidate(w)
	check(WorldSociety.active(w, h, "carpentry"), "trained successor resumes the craft without a second invention")
	WorldEconomy.plan(w, h)
	check(WorldEconomy.count(w, h, "workshop", false) == 1 and not w.buildings.back().ready, "carpentry unlocks a real workshop construction project")
	check(ledger(w), "planned workshop has no free delivered timber")

	var coast := WorldState.new()
	for x in range(7): coast.paint(Vector2i(x, 0), 0, WorldState.Terrain.GRASS)
	for y in [1, 2]:
		for x in [6, 7]: coast.paint(Vector2i(x, y), 0, WorldState.Terrain.GRASS)
	var coast_home := {"id": coast.next_id, "name": "Косой берег", "x": 0, "y": 0, "food": 0, "wood": 0, "level": 1}
	coast.next_id += 1
	coast.towns.append(coast_home)
	WorldEconomy.add_building(coast, coast_home, "camp", Vector2i.ZERO, true)
	check(WorldEconomy.site(coast, coast_home, "archive") == Vector2i(6, 1), "construction finds a reachable off-ray coastal plot")
	coast.ignite(Vector2i(6, 1), 0)
	check(WorldEconomy.site(coast, coast_home, "archive") == WorldState.NO_CELL, "coastal fallback respects fires and the entire footprint")
	w = fixture()
	h = w.towns[0]
	s = w.societies[0]
	for key in WorldSociety.TECH: master(w, key)
	for kind in ["workshop", "archive"]:
		var b := WorldEconomy.add_building(w, h, kind, Vector2i(5, -5) if kind == "workshop" else Vector2i(-4, -2), true)
		w.metrics.harvested_wood += WorldEconomy.COST[kind]
		w.metrics.built_wood += WorldEconomy.COST[kind]
	check(WorldSociety.active(w, h, "records"), "records require the archive and experienced local people")
	s.tech.carpentry.used = 1
	s.tech.preservation.used = 1
	s.tech.rotation.used = 1
	s.tech.records.used = 1
	s.taught = 1
	WorldSociety.daily(w)
	var profile := WorldDevelopment.profile(w, h)
	check(profile.food.mastered == 2 and profile.maritime.mastered == 2 and profile.education.mastered == 1, "capabilities develop in independent domains without advancing a global era")
	h.food = 0
	WorldSociety.daily(w)
	check(s.era == 0 and s.era_days == 0 and profile.food.mastered == 2, "food crisis retains knowledge without a global stage")
	h.food = 48
	WorldSociety.daily(w)
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(w.to_dict()))) != null, "advanced society and infrastructure load")
	var child: Dictionary = w.people[2]
	child.birth_tick = -13 * WorldLife.YEAR
	child.job = "teen"
	for skill in child.skills: child.skills[skill] = 0
	child.parents = [int(w.people[0].id), int(w.people[1].id)]
	child.ancestors = child.parents.duplicate()
	child.generation = 2
	child.guardian = int(w.people[0].id)
	worker = w.people[0]
	worker.ideas = ["records", "carpentry"]
	child.x = 0
	child.y = 0
	WorldLife.reconcile(w)
	check(WorldSocial.offer_lesson(w, child, h), "archive lesson still requires a real available mentor")
	check(WorldSocial.describe(w, child).contains("/8"), "pupil card shows the actual archive lesson duration")
	for i in 7: WorldSocial.teach(w, worker, h)
	check(not child.lesson.is_empty() and child.skills.build == 0, "archive cannot grant knowledge before the required meeting work")
	WorldSocial.teach(w, worker, h)
	check(child.lesson.is_empty() and not child.trained_by.is_empty() and child.ideas.has("records"), "eighth meeting step completes a bounded lesson and shares known ideas")
	check(s.tech.records.used == 2 and ledger(w), "archive teaching records a real use without creating food")
	var archive_cell := Vector2i(-4, -2)
	w.paint(archive_cell, 0, WorldState.Terrain.WATER)
	check(not WorldSociety.active(w, h, "records") and WorldSocial.lesson_work(w, h) == 10 and s.tech.records.mastered and s.era == 0, "destroyed archive stops the benefit but retains recipe and historical stage")
	check(WorldState.from_dict(w.to_dict()) != null and ledger(w), "archive destruction preserves balanced resources and a loadable society")

	w.paint(Vector2i(100, 0), 15, WorldState.Terrain.GRASS)
	var remote := {"id": w.next_id, "name": "Дальний берег", "x": 100, "y": 0, "food": 30, "wood": 0, "level": 1}
	w.next_id += 1
	w.towns.append(remote)
	WorldEconomy.add_building(w, remote, "camp", Vector2i(100, 0), true)
	var other_society := WorldSociety.get_society(w, remote.id)
	WorldSociety.daily(w)
	check(other_society.era == 0 and not other_society.tech.carpentry.known and s.era == 0, "distant settlements keep separate ideas and eras")
	worker = w.people[0]
	worker.ideas = ["carpentry"]
	worker.home = remote.id
	w.population_dirty = true
	WorldSociety.daily(w)
	check(not other_society.tech.carpentry.known, "home tag without physical arrival cannot transmit knowledge")
	worker.x = 100
	worker.y = 0
	WorldSociety.invalidate(w)
	WorldLife.reconcile(w)
	WorldSociety.daily(w)
	check(other_society.tech.carpentry.known and not other_society.tech.carpentry.mastered and other_society.tech.carpentry.progress == 0, "arriving carrier shares an idea that still needs local adoption")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(w.to_dict()))) != null, "knowledge carrier and separate societies roundtrip")
	w = fixture()
	h = w.towns[0]
	s = w.societies[0]
	s.tech.carpentry.known = true
	s.project = "carpentry"
	worker = w.people[0]
	WorldSociety.research_assign(w, worker, h)
	WorldEconomy.execute(w, worker, h)
	w.remove_person(w.people.find(worker), "проверка потери исследователя")
	check(s.worker == -1 and s.tech.carpentry.progress == 1 and not s.tech.carpentry.mastered, "researcher's death frees the task but retains invested work")
	check(WorldState.from_dict(w.to_dict()) != null and ledger(w), "researcher loss leaves no dangling worker or cargo")
	w = fixture()
	h = w.towns[0]
	s = w.societies[0]
	for key in ["carpentry", "preservation", "records"]: master(w, key)
	var workshop := WorldEconomy.add_building(w, h, "workshop", Vector2i(5, -5), true)
	w.metrics.harvested_wood += WorldEconomy.COST.workshop
	w.metrics.built_wood += WorldEconomy.COST.workshop
	s.tech.carpentry.used = 1
	s.tech.preservation.used = 1
	check(WorldDevelopment.profile(w, h).engineering.mastered == 1 and not s.tech.rotation.mastered, "engineering develops independently of farming")
	check(not WorldSociety.active(w, h, "records") and WorldSociety.description(w, h).contains("архив"), "records still need actual operating archives")
	w = fixture()
	w.metrics.births = 7
	w.metrics.deaths = 3
	w.metrics.lessons = 5
	w.metrics.helped_food = 2
	var legacy := w.to_dict()
	legacy.version = 5
	legacy.erase("societies")
	legacy.metrics.erase("discoveries")
	legacy.metrics.erase("research_work")
	for p in legacy.people: p.erase("ideas")
	var upgraded := WorldState.from_dict(JSON.parse_string(JSON.stringify(legacy)))
	check(upgraded != null and upgraded.towns == w.towns and upgraded.people[0].skills == w.people[0].skills and upgraded.households == w.households, "v5 migration retains resources, skills and family data")
	if upgraded != null:
		check(upgraded.metrics.births == 7 and upgraded.metrics.deaths == 3 and upgraded.metrics.lessons == 5 and upgraded.metrics.helped_food == 2, "older demographic and social counters survive migration")
		check(not upgraded.societies[0].tech.carpentry.mastered and upgraded.people[0].ideas.is_empty(), "migration gives no automatic technology")
		check(WorldState.from_dict(upgraded.to_dict()) != null, "migrated v5 saves as v6")
	for mutation in ["missing", "duplicate", "town", "xp", "progress", "mastered", "era", "worker", "ideas", "crop"]:
		var broken := fixture().to_dict()
		match mutation:
			"missing": broken.erase("societies")
			"duplicate": broken.societies.append(broken.societies[0].duplicate(true))
			"town": broken.societies[0].town = -1
			"xp": broken.societies[0].practice.food = -1
			"progress": broken.societies[0].tech.preservation.progress = 61
			"mastered": broken.societies[0].tech.preservation.mastered = true
			"era": broken.societies[0].era = 4
			"worker": broken.societies[0].worker = broken.people[0].id
			"ideas": broken.people[0].ideas = ["magic"]
			"crop": broken.buildings[2].stock = 24
		check(WorldState.from_dict(broken) == null, "malformed society rejected: " + mutation)
	print("Society: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
