extends SceneTree
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func settlement(world: WorldState, center: Vector2i, population: int) -> Dictionary:
	world.paint(center, 14, WorldState.Terrain.GRASS)
	world.paint(center + Vector2i(9, 0), 4, WorldState.Terrain.FOREST)
	var home := {"id": world.next_id, "name": "Группа %d" % world.next_id, "x": center.x, "y": center.y, "food": 48, "wood": 24, "level": 1}
	world.next_id += 1
	world.towns.append(home)
	WorldEconomy.add_building(world, home, "camp", center, true)
	world.metrics.spawn_food += 48
	world.metrics.harvested_wood += 24
	for i in population:
		world.add_person(center + Vector2i(i % 10 - 5, i / 10 - 5), false)
		world.people.back().home = home.id
	WorldLife.reconcile(world)
	return home

func ids(values: Array) -> Array:
	var result := []
	for value in values: result.append(value.id)
	return result

func exact_food_days(world: WorldState, home: Dictionary) -> float:
	var need := 0.0
	for member in WorldEconomy.members(world, home): need += WorldLife.hunger_rate(world, member) * WorldEconomy.DAY_TICKS / WorldEconomy.NUTRITION
	return home.food / maxf(0.25, need)

func run() -> void:
	var world := WorldState.new()
	var home := settlement(world, Vector2i(-64, -32), 100)
	var center := Vector2i(-64, -32)
	var reference := world.population.nearby(world, center, 9, home.id)
	world.population.active = true
	world.population.rebuild(world)
	check(ids(world.population.nearby(world, center, 9, home.id)) == ids(reference), "spatial queries preserve global order across negative bucket borders")
	check(world.population.nearby(world, center, 9, -999).is_empty(), "nearby query respects actual settlement")
	var options := {"limit": 3, "after_id": world.people[20].id, "local": true}
	world.population.active = false
	var bounded := ids(world.population.nearby(world, center, 100, home.id, options))
	world.population.active = true
	check(ids(world.population.nearby(world, center, 100, home.id, options)) == bounded, "bounded contact queries preserve the same first three eligible people")
	world.people.reverse()
	world.population.ready = false
	world.population.active = false
	bounded = ids(world.population.nearby(world, center, 100, home.id, options))
	world.population.active = true; world.population.rebuild(world)
	check(not world.population.monotonic_ids and ids(world.population.nearby(world, center, 100, home.id, options)) == bounded, "shuffled valid population uses stable order without the ID shortcut")
	world.people.reverse(); world.population.rebuild(world)
	var member: Dictionary = world.people[0]
	var old := Vector2i(member.x, member.y)
	member.x = center.x; member.y = center.y
	world.track_person_move(member, old)
	check(world.population.nearby(world, center, 0, home.id).has(member), "moving between buckets updates nearby index")
	member.guardian = int(world.people[1].id)
	member.birth_tick = -4 * WorldLife.YEAR
	world.population.ready = false
	check(world.population.children(world, world.people[1]).has(member), "guardian index includes real child")
	check(WorldLife.care_candidate(world, world.people[1]).id == member.id, "indexed urgent care keeps the child's identity")
	member.birth_tick = -25 * WorldLife.YEAR; member.guardian = -1
	world.population.ready = false
	world.workforce.begin(world)
	var plan := world.workforce.context(world, home)
	check(plan.population == 100, "one plan includes all adults")
	var builds := world.workforce.plan_builds
	for i in 500: WorldEconomy.food_days(world, home)
	check(world.workforce.plan_builds == builds, "repeated demand queries reuse one settlement plan")
	check(is_equal_approx(WorldEconomy.food_days(world, home), exact_food_days(world, home)), "shared food demand matches individual needs")
	for i in 65:
		WorldEconomy.set_task(world, world.people[i], WorldEconomy.task("gather_food", center + Vector2i(i % 13 - 6, i / 13 - 6)))
	check(plan.food_workers == 65 and world.workforce.group_count(world, home) == 3, "65 food workers share a plan in groups bounded by 32")
	WorldEconomy.set_task(world, world.people[0], {})
	check(plan.food_workers == 64 and world.workforce.group_count(world, home) == 2, "leaving a work group updates live allocation")
	for person in world.people: WorldEconomy.set_task(world, person, {})
	var targets := {}
	var unique := true
	for i in 40:
		var target := WorldEconomy.resource(world, world.people[i], home, "food")
		if target == WorldState.NO_CELL: continue
		if targets.has(target): unique = false
		targets[target] = true
		WorldEconomy.set_task(world, world.people[i], WorldEconomy.task("gather_food", target))
	check(unique and targets.size() == 40, "shared resource batches issue distinct physical jobs across a 32-job boundary")
	check(world.workforce.context(world, home).resources.food.offers.size() <= WorldWorkforce.GROUP_SIZE, "job offer queue stays bounded")
	var supplied := WorldEconomy.add_building(world, home, "house", center + Vector2i(4, 4))
	var worker: Dictionary = world.people[0]
	worker.cargo = 3; worker.cargo_kind = "wood"
	WorldEconomy.set_task(world, worker, WorldEconomy.task("supply", center, supplied.id))
	check(WorldEconomy.in_transit(world, supplied.id) == 3, "material reservation still belongs to a real carrier")
	WorldEconomy.set_task(world, worker, {})
	check(WorldEconomy.in_transit(world, supplied.id) == 0, "interruption releases the construction reservation")
	worker.cargo = 0; worker.cargo_kind = ""
	check(WorldEconomy.count(world, home, "house", false) == 1, "new construction immediately joins the shared building index")
	var other_home := {"id": world.next_id, "x": center.x, "y": center.y, "food": 24, "wood": 24, "level": 1}
	world.next_id += 1; world.towns.append(other_home)
	var other_plan := world.workforce.context(world, other_home)
	var original_count: int = plan.population
	var original_need: float = plan.warm_need + plan.cold_need
	WorldEconomy.set_home(world, worker, other_home.id)
	check(not WorldEconomy.members(world, home).has(worker) and WorldEconomy.members(world, other_home) == [worker], "rehoming updates both membership lists without a global rebuild")
	check(plan.population == original_count - 1 and other_plan.population == 1, "rehoming updates both shared adult counts")
	check(is_equal_approx(plan.warm_need + plan.cold_need + other_plan.warm_need + other_plan.cold_need, original_need), "rehoming preserves total individual food demand")
	WorldEconomy.set_home(world, worker, home.id)
	check(WorldEconomy.members(world, home)[0].id == worker.id and other_plan.population == 0, "returning a resident preserves global order and removes the old contribution")
	world.workforce.end(); world.population.active = false
	WorldLife.reconcile(world)
	var saved := JSON.stringify(world.to_dict())
	world.population.active = true; world.population.rebuild(world)
	world.workforce.begin(world)
	WorldEconomy.food_days(world, home); WorldEconomy.resource(world, world.people[60], home, "food")
	check(JSON.stringify(world.to_dict()) == saved, "plans, spatial buckets and offers are derived and do not alter a snapshot")
	world.workforce.end(); world.population.active = false

	var climate_world := WorldState.new()
	var climate_home := settlement(climate_world, Vector2i.ZERO, 8)
	var cold_person: Dictionary = climate_world.people[0]
	var cold_cell := Vector2i(cold_person.x, cold_person.y)
	climate_world.biome_overrides[cold_cell] = 4
	climate_world.workforce.begin(climate_world)
	check(is_equal_approx(WorldEconomy.food_days(climate_world, climate_home), exact_food_days(climate_world, climate_home)), "group demand accounts for individual cold exposure")
	WorldCivilization.ensure(climate_world, climate_home).stock.cloth = 1
	check(is_equal_approx(WorldEconomy.food_days(climate_world, climate_home), exact_food_days(climate_world, climate_home)), "clothing changes the demand immediately within a step")
	cold_person.x = 8; cold_person.y = 0
	climate_world.track_person_move(cold_person, cold_cell)
	check(is_equal_approx(WorldEconomy.food_days(climate_world, climate_home), exact_food_days(climate_world, climate_home)), "crossing a biome updates individual contribution")
	climate_world.workforce.end()


	var dense := WorldState.new()
	var dense_home := settlement(dense, Vector2i.ZERO, 100)
	check(WorldEconomy.storage_pressure(dense, dense_home) and WorldEconomy.food_days(dense, dense_home) < 2, "full dense camp detects an impossible two-day storage reserve")
	dense.workforce.begin(dense)
	WorldEconomy.plan(dense, dense_home)
	var store: Dictionary = dense.buildings.back()
	check(store.kind == "store" and not store.ready and store.delivered == 0, "dense camp plans real storage without granting materials")
	for i in 51: WorldEconomy.set_task(dense, dense.people[i], WorldEconomy.task("gather_food", Vector2i(i % 10, i / 10)))
	var carrier: Dictionary = dense.people[60]
	carrier.x = 0; carrier.y = 0
	WorldEconomy.assign(dense, carrier, dense_home)
	check(carrier.task.get("kind") == "supply" and carrier.task.building == store.id, "food shortage caused by capacity allows a storage carrier after food workers")
	for batch in 2:
		carrier.x = 0; carrier.y = 0
		WorldEconomy.set_task(dense, carrier, WorldEconomy.task("supply", Vector2i.ZERO, store.id))
		for i in 16:
			if carrier.task.is_empty(): break
			WorldEconomy.execute(dense, carrier, dense_home)
	check(store.delivered == 12 and dense_home.wood == 12, "emergency store consumes twelve physically delivered wood")
	WorldEconomy.set_task(dense, carrier, WorldEconomy.task("build", Vector2i(store.x, store.y), store.id))
	for i in 24:
		if store.ready: break
		WorldEconomy.execute(dense, carrier, dense_home)
	check(store.ready and dense.metrics.built_wood == 12, "emergency store requires ordinary construction work")
	check(WorldAudit.conserved(dense), "storage expansion conserves all resources")
	check(WorldEconomy.food_capacity(dense, dense_home) >= WorldEconomy.daily_need(dense, dense_home) * 2, "completed store can hold the reserve needed for further development")
	dense.workforce.end()

	var large := WorldState.new()
	for i in 20: settlement(large, Vector2i((i % 5) * 64, (i / 5) * 64), 100)
	check(large.people.size() == 2000, "world supports 2000 distinct people")
	check(not large.add_person(Vector2i.ZERO, false), "population cap rejects an extra person")
	for i in 21: large.step()
	check(large.people.size() == 2000, "2000 people remain individually alive after shared planning")
	check(WorldAudit.conserved(large), "maximum population conserves all eight materials")
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(large.to_dict())))
	check(loaded != null, "maximum population restores from JSON")
	if loaded != null:
		check(JSON.stringify(loaded.to_dict()) == JSON.stringify(large.to_dict()), "expanded population preserves families, skills, tasks and cargo")
		for i in 21: large.step(); loaded.step()
		check(JSON.stringify(loaded.to_dict()) == JSON.stringify(large.to_dict()), "derived plans rebuild deterministically after loading")
		check(WorldAudit.conserved(large) and WorldAudit.conserved(loaded), "both resumed worlds conserve resources")
	var path := "user://population-test.json"
	check(SaveStore.save_world(large, path) == OK, "maximum-size regional snapshot writes successfully")
	var disk := SaveStore.load_world(path)
	check(disk != null and JSON.stringify(disk.to_dict()) == JSON.stringify(large.to_dict()), "2000-person disk save reloads exactly")
	var fixture := FileAccess.open("res://artifacts/population-2000-world.json", FileAccess.WRITE)
	if fixture != null: fixture.store_string(JSON.stringify(large.to_dict())); fixture.close()
	DirAccess.remove_absolute(path)
	var previous := climate_world.to_dict()
	previous.version = 7
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(previous))) != null, "0.1.0 v7 snapshots migrate without replacing people")
	var dead_id: int = large.people[0].id
	large.population.active = true; large.population.rebuild(large)
	large.remove_person(0, "проверка индекса")
	check(not large.person_index.has(dead_id), "death removes the authoritative identity")
	check(not ids(large.population.nearby(large, Vector2i.ZERO, 10000)).has(dead_id), "death invalidates derived spatial results")
	large.population.active = false
	check(large.add_person(Vector2i.ZERO, false) and large.people.size() == 2000, "vacated population slot accepts a new distinct person")

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	run()
	print("Population: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
