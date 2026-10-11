extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func fixture(coastal: bool = false) -> WorldState:
	var world := WorldState.new()
	world.paint(Vector2i.ZERO, 18 if coastal else 36, WorldState.Terrain.GRASS)
	world.paint(Vector2i(10, 0), 4, WorldState.Terrain.FOREST)
	if not coastal: world.paint(Vector2i(20, 0), 0, WorldState.Terrain.WATER)
	var home := {"id": world.next_id, "name": "Мастерская", "x": 0, "y": 0, "food": 120, "wood": 64, "level": 3}
	world.next_id += 1
	world.towns.append(home)
	world.metrics.spawn_food += home.food
	world.metrics.harvested_wood += home.wood
	for spec in [["camp", Vector2i.ZERO], ["store", Vector2i(-7, -7)], ["house", Vector2i(4, 4)], ["farm", Vector2i(-7, 4)], ["workshop", Vector2i(4, -7)], ["dock", Vector2i(0, 16)]]:
		var building := WorldEconomy.add_building(world, home, spec[0], spec[1], true)
		world.metrics.harvested_wood += WorldEconomy.COST[building.kind]
		world.metrics.built_wood += WorldEconomy.COST[building.kind]
	for i in 3:
		world.add_person(Vector2i(i, 0), false)
		var member: Dictionary = world.people.back()
		member.home = home.id
		member.sex = "male"
		member.birth_tick = -25 * WorldLife.YEAR
		for skill in member.skills: member.skills[skill] = 120
	WorldLife.reconcile(world)
	return world

func copy(world: WorldState) -> WorldState:
	return WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))

func candidate(options: Array[Dictionary], key: String) -> Dictionary:
	for value in options:
		if value.key == key: return value
	return {}

func start(world: WorldState, key: String) -> Dictionary:
	var home: Dictionary = world.towns[0]
	var society: Dictionary = world.societies[0]
	society.tech[key].known = true
	society.project = key
	var member: Dictionary = world.people[0]
	check(WorldSociety.research_assign(world, member, home), "a feasible experiment receives a real worker")
	return member

func work(world: WorldState, member: Dictionary, count: int) -> void:
	for i in count:
		if member.task.get("kind") != "research": return
		member.energy = 100.0
		world.ticks += 1
		WorldSociety.research(world, member, world.towns[0])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := fixture()
	var home: Dictionary = world.towns[0]
	var society: Dictionary = world.societies[0]
	for key in ["carpentry", "rotation", "navigation"]: society.tech[key].known = true
	var inland := WorldDevelopment.candidates(world, home)
	var coast := fixture(true)
	for key in ["carpentry", "rotation", "navigation"]: coast.societies[0].tech[key].known = true
	var coastal := WorldDevelopment.candidates(coast, coast.towns[0])
	check(candidate(coastal, "navigation").weight > candidate(inland, "navigation").weight * 5, "reachable coast substantially increases maritime project weight")
	check(inland.size() == 3 and coastal.size() == 3, "environment changes preference while retaining multiple feasible projects")
	var choices := {}
	var sea_inland := 0
	var sea_coast := 0
	for seed_value in 256:
		world.world_seed = seed_value
		coast.world_seed = seed_value
		WorldDevelopment.initialize(world, society)
		WorldDevelopment.initialize(coast, coast.societies[0])
		WorldDevelopment.choose(world, home, society)
		WorldDevelopment.choose(coast, coast.towns[0], coast.societies[0])
		choices[society.project] = true
		sea_inland += int(society.project == "navigation")
		sea_coast += int(coast.societies[0].project == "navigation")
	check(choices.size() == 3 and sea_coast > sea_inland * 2, "different seeds give multiple histories and coast increases actual maritime selections")
	var rng_before: int = society.choice_rng
	var project_before: String = society.project
	WorldSociety.daily(world)
	check(society.choice_rng == rng_before and society.project == project_before, "an ongoing feasible project is retained without a fresh daily lottery")
	var loaded := copy(world)
	check(loaded != null, "selected projects and independent random streams save")
	if loaded != null:
		society.project = ""
		loaded.societies[0].project = ""
		WorldDevelopment.choose(world, home, society)
		WorldDevelopment.choose(loaded, loaded.towns[0], loaded.societies[0])
		check(society.project == loaded.societies[0].project and society.choice_rng == loaded.societies[0].choice_rng, "next project selection is identical after loading")
	home.food = 0
	check(WorldDevelopment.candidates(world, home).is_empty(), "hunger removes all research candidates regardless of their weight")
	home.food = 120
	home.wood = 0
	check(not WorldSociety.reason(world, home, "navigation").is_empty() and candidate(WorldDevelopment.candidates(world, home), "navigation").is_empty(), "an appealing coast cannot replace missing shipbuilding materials")

	world = fixture(true)
	home = world.towns[0]
	society = world.societies[0]
	check(WorldSociety.reason(world, home, "navigation").is_empty() and not society.tech.carpentry.mastered and not society.tech.preservation.mastered, "navigation can be independently explored with equipment, supplies and a specialist")
	var member := start(world, "navigation")
	work(world, member, 1)
	check(home.wood == 63 and society.tech.navigation.spent and WorldAudit.conserved(world), "starting an experiment consumes exactly its recorded materials")
	var threshold: float = society.tech.navigation.threshold
	var stream: int = society.tech.navigation.experiment_rng
	var reserved: int = home.wood
	work(world, member, 12)
	check(not society.tech.navigation.mastered and society.tech.navigation.threshold == threshold and society.tech.navigation.experiment_rng == stream and home.wood == reserved, "preparation takes actual work without rerolling or repeatedly consuming supplies")
	loaded = copy(world)
	check(loaded != null, "an active experiment saves its threshold, accumulated work and paid materials")
	if loaded != null:
		for i in 50:
			world.step()
			var sliced := WorldStepJob.new(loaded)
			while not sliced.finished: sliced.advance(200)
		check(JSON.stringify(world.to_dict()) == JSON.stringify(loaded.to_dict()), "saved experiments, research choices and discoveries match full and sliced simulation")
	check(WorldAudit.conserved(world), "research and production retain all material balances")

	world = fixture()
	home = world.towns[0]
	society = world.societies[0]
	member = start(world, "carpentry")
	work(world, member, 1)
	society.tech.carpentry.threshold = 20.0
	work(world, member, int(WorldSociety.TECH.carpentry.work) * 2)
	check(member.task.is_empty() and society.worker == -1 and society.project.is_empty() and society.tech.carpentry.retry_tick > world.ticks and not society.tech.carpentry.mastered, "a bounded failed experiment frees the worker and records a retry delay")
	check(society.tech.carpentry.progress == WorldSociety.TECH.carpentry.work and society.tech.carpentry.work_done == WorldSociety.TECH.carpentry.work * 2, "nominal recipe work does not guarantee a discovery and actual work remains recorded")
	check(candidate(WorldDevelopment.candidates(world, home), "carpentry").is_empty() and copy(world) != null and WorldAudit.conserved(world), "failed attempt memory saves and prevents an immediate retry")
	world.ticks = society.tech.carpentry.retry_tick
	check(not candidate(WorldDevelopment.candidates(world, home), "carpentry").is_empty(), "a later attempt is possible after the recorded pause")
	member = start(world, "carpentry")
	work(world, member, 1)
	check(home.wood == 62 and society.tech.carpentry.attempts == 2, "a retry uses a fresh saved threshold and a new paid batch")

	world = fixture(true)
	home = world.towns[0]
	society = world.societies[0]
	var stock: Dictionary = WorldCivilization.ensure(world, home).stock
	stock.cloth = 1
	world.industry.produced.cloth = 1
	check(WorldSociety.reason(world, home, "sailing").is_empty() and not society.tech.navigation.mastered and not society.tech.weaving.mastered, "available cloth allows a sail experiment without mandatory navigation or weaving predecessors")
	stock.cloth = 0
	check(WorldSociety.reason(world, home, "sailing").contains("Ткань"), "a sail experiment still requires actual cloth")
	var kiln := WorldEconomy.add_building(world, home, "kiln", Vector2i(-12, 0), true)
	world.metrics.harvested_wood += WorldEconomy.COST.kiln
	world.metrics.built_wood += WorldEconomy.COST.kiln
	world.industry.produced.stone += kiln.materials.stone
	stock.stone = 1
	world.industry.produced.stone += 1
	check(WorldSociety.reason(world, home, "ceramics").is_empty() and not society.tech.stonework.mastered, "heat equipment and delivered materials permit ceramics without a named stonework prerequisite")
	check(WorldDevelopment.construction_ready(world, home, "market") and not society.tech.records.mastered and not society.tech.metallurgy.mastered, "civic infrastructure does not require a fixed technology chain")
	var profile := WorldDevelopment.profile(world, home)
	check(profile.food.mastered == 0 and profile.maritime.mastered == 0 and profile.science.practice == 0, "unrelated domains gain no free progress from equipment")

	var durations := {}
	var successful := 0
	for seed_value in 48:
		world = fixture()
		world.world_seed = seed_value
		WorldDevelopment.initialize(world, world.societies[0])
		member = start(world, "preservation")
		work(world, member, 120)
		var state: Dictionary = world.societies[0].tech.preservation
		if state.mastered:
			successful += 1
			durations[int(state.work_done)] = true
			check(state.work_done >= 16, "a random success still requires real preparation")
	check(successful >= 30 and durations.size() >= 10, "equal environments have varied discovery times across saved random streams")
	world = fixture()
	member = start(world, "carpentry")
	work(world, member, 10)

	var legacy := world.to_dict()
	legacy.version = 9
	for value in legacy.societies:
		for field in ["choice_rng", "project_reason", "domain_practice"]: value.erase(field)
		for state in value.tech.values():
			for field in ["experiment_rng", "threshold", "intensity", "attempts", "attempt_work", "work_done", "retry_tick", "spent"]: state.erase(field)
	loaded = WorldState.from_dict(JSON.parse_string(JSON.stringify(legacy)))
	check(loaded != null and loaded.societies[0].tech.carpentry.progress == 10 and not loaded.societies[0].tech.carpentry.mastered, "v9 migration preserves an unfinished project without gifting a discovery")
	check(loaded != null and loaded.towns == world.towns and loaded.people == world.people and WorldState.from_dict(loaded.to_dict()) != null, "migration preserves resources, people and subsequent v10 saves")
	for mutation in ["rng", "stream", "threshold", "intensity", "attempt", "work", "paid", "cooldown", "domain", "missing"]:
		var broken := world.to_dict()
		var state: Dictionary = broken.societies[0].tech.carpentry
		match mutation:
			"rng": broken.societies[0].choice_rng = 0
			"stream": state.experiment_rng = WorldDevelopment.RANDOM_MODULUS
			"threshold": state.threshold = -1
			"intensity": state.intensity = "wrong"
			"attempt": state.attempt_work = 999
			"work": state.work_done = -1
			"paid": state.spent = "true"
			"cooldown": state.retry_tick = -1
			"domain": broken.societies[0].domain_practice.food = -1
			"missing": state.erase("threshold")
		check(WorldState.from_dict(broken) == null, "malformed experimental state rejected: " + mutation)
	print("Development: %d checks, %d failures; maritime choices inland %d, coast %d." % [checks, failures, sea_inland, sea_coast])
	quit(1 if failures else 0)
