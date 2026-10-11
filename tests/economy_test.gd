extends SceneTree

var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func settlement(population: int = 1, food_stock: int = 0, wood_stock: int = 0) -> WorldState:
	var world := WorldState.new()
	world.paint(Vector2i.ZERO, 14, WorldState.Terrain.GRASS)
	world.paint(Vector2i(7, 0), 3, WorldState.Terrain.FOREST)
	var home := {"id": world.next_id, "name": "Испытательный берег", "x": 0, "y": 0, "food": food_stock, "wood": wood_stock, "level": 1}
	world.next_id += 1
	world.towns.append(home)
	WorldEconomy.add_building(world, home, "camp", Vector2i.ZERO, true)
	for i in population:
		world.add_person(Vector2i(0, i), false)
		world.people.back().home = home.id

	world.metrics.spawn_food += food_stock
	world.metrics.harvested_wood += wood_stock
	return world

func advance(world: WorldState, ticks: int) -> void:
	for i in ticks: world.step()

func ledger(world: WorldState, context: String) -> void:
	var stored_food := 0
	var stored_wood := 0
	for family in world.households: stored_food += family.food
	for home in world.towns:
		stored_food += home.food
		stored_wood += home.wood
	for person in world.people:
		stored_food += person.rations
		if person.cargo_kind in ["food", "seed"]: stored_food += person.cargo
		if person.cargo_kind == "wood": stored_wood += person.cargo
	for value in world.buildings:
		stored_food += value.stock
		if not value.ready: stored_wood += value.delivered
	for ship in world.voyages + world.journeys:
		stored_food += ship.food
		if ship.cargo_kind == "food": stored_food += ship.cargo
		if ship.cargo_kind == "wood": stored_wood += ship.cargo
	var m := world.metrics
	var food_in: int = m.spawn_food + m.harvested_food + m.crop_food
	var food_out: int = m.eaten_food + m.seed_food + m.spoiled_food + m.growth_food + m.lost_food + m.processed_food
	var wood_out: int = m.built_wood + m.growth_wood + m.lost_wood + m.processed_wood
	check(food_in == stored_food + food_out, context + ": food conserved across all inventories and sinks")
	check(m.harvested_wood == stored_wood + wood_out, context + ": timber conserved through delivery, construction and loss")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := settlement()
	var home: Dictionary = world.towns[0]
	var person: Dictionary = world.people[0]
	var source := Vector2i(4, 0)
	var old_food := world.food_at(source)
	var gathered := mini(WorldEconomy.LOAD, old_food)
	WorldEconomy.set_task(world, person, WorldEconomy.task("gather_food", source))
	var adjacent_steps := true
	for i in 12:
		var before := Vector2i(person.x, person.y)
		WorldEconomy.execute(world, person, home)
		if before.distance_to(Vector2i(person.x, person.y)) > 1: adjacent_steps = false
		if person.cargo > 0: break
	check(adjacent_steps and Vector2i(person.x, person.y) == source, "worker walks to source one adjacent cell at a time")
	check(home.food == 0 and person.cargo == gathered and world.food_at(source) == old_food - gathered, "harvesting transfers ground food to cargo without crediting the town")
	WorldEconomy.set_task(world, person, WorldEconomy.task("deliver", Vector2i.ZERO))
	WorldEconomy.execute(world, person, home)
	check(home.food == 0 and person.cargo == gathered, "distant cargo cannot instantly reach storage")
	for i in 12:
		WorldEconomy.execute(world, person, home)
		if person.cargo == 0: break
	check(home.food == gathered and person.cargo == 0, "only arrival transfers cargo to stock")
	ledger(world, "forage and delivery")
	person.hunger = 20
	var stock_before: int = home.food
	var eaten_before: int = world.metrics.eaten_food
	world.step()
	check(home.food == stock_before and world.metrics.eaten_food == eaten_before + 1, "eating rations consumes food without creating town stock")
	ledger(world, "eating")

	world = settlement(2, 30, 6)
	home = world.towns[0]
	person = world.people[0]
	var project := WorldEconomy.add_building(world, home, "house", Vector2i(-5, -4))
	for i in 20: WorldEconomy.plan(world, home)
	check(not project.ready and project.work == 0 and project.delivered == 0 and home.wood == 6, "a funded project does not build or deduct wood without workers")
	WorldEconomy.set_task(world, person, WorldEconomy.task("supply", Vector2i.ZERO, project.id))
	WorldEconomy.execute(world, person, home)
	check(home.wood == 0 and person.cargo == 6 and project.delivered == 0, "construction materials physically leave stock into worker cargo")
	var active_before: Dictionary = person.task.duplicate()
	world.paint(Vector2i(-900000, 700000), 2, WorldState.Terrain.FOREST)
	check(person.task == active_before and person.cargo == 6, "creating a distant island preserves an unrelated active delivery")
	var midway := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(midway != null and JSON.stringify(midway.to_dict()) == JSON.stringify(world.to_dict()), "save restores an unfinished building and material cargo exactly")
	var other: Dictionary = world.people[1]
	other.x = 0
	other.y = 0
	WorldEconomy.set_task(world, other, WorldEconomy.task("supply", Vector2i.ZERO, project.id))
	WorldEconomy.execute(world, other, home)
	check(other.cargo == 0 and person.cargo == 6 and other.task.is_empty(), "another supplier cannot withdraw material already carried by the first")
	for i in 24:
		WorldEconomy.execute(world, person, home)
		if project.delivered == 6: break
	check(project.delivered == 6 and not project.ready, "delivered material still requires building labor")
	WorldEconomy.set_task(world, person, WorldEconomy.task("build", Vector2i(project.x, project.y), project.id))
	for i in 16: WorldEconomy.execute(world, person, home)
	check(project.ready and WorldEconomy.housing(world, home) == 8 and world.metrics.built_wood == 6, "completed house increases real housing capacity and consumes six timber")
	ledger(world, "construction")
	if midway != null:
		var second := WorldState.from_dict(JSON.parse_string(JSON.stringify(midway.to_dict())))
		for i in 240:
			midway.step()
			second.step()
		check(JSON.stringify(midway.to_dict()) == JSON.stringify(second.to_dict()), "material delivery and construction continue identically after reload")

	world = settlement()
	home = world.towns[0]
	person = world.people[0]
	source = Vector2i(7, 0)
	person.x = source.x
	person.y = source.y
	for round_value in 4:
		WorldEconomy.set_task(world, person, WorldEconomy.task("gather_wood", source))
		for i in 4: WorldEconomy.execute(world, person, home)
		WorldEconomy.set_task(world, person, WorldEconomy.task("deliver", Vector2i.ZERO))
		for i in 30:
			WorldEconomy.execute(world, person, home)
			if person.cargo == 0: break
		person.x = source.x
		person.y = source.y
	check(world.wood_at(source) == 0 and world.terrain_at(source) == WorldState.Terrain.GRASS and home.wood == 12, "four timber loads exhaust a forest cell and leave grass")
	ledger(world, "forest exhaustion")

	world = settlement(1, 10)
	home = world.towns[0]
	person = world.people[0]
	var farm := WorldEconomy.add_building(world, home, "farm", Vector2i(-6, 0), true)
	WorldEconomy.set_task(world, person, WorldEconomy.task("plant", Vector2i(farm.x, farm.y), farm.id))
	WorldEconomy.prepare_seed(world, person, home)
	check(home.food == 9 and person.cargo_kind == "seed" and person.cargo == 1 and not farm.planted, "seed comes from food stock and travels with the farmer")
	for i in 20:
		WorldEconomy.execute(world, person, home)
		if farm.planted: break
	check(farm.planted and person.cargo == 0 and world.metrics.seed_food == 1, "sowing needs travel, seed and work")

	WorldEconomy.set_task(world, person, WorldEconomy.task("rest", Vector2i(person.x, person.y)))
	person.energy = 0
	world.drought_until = 1000
	advance(world, 20)
	check(farm.growth == 0 and farm.stock == 0, "drought pauses growth and does not invent a harvest")
	world.rain(Vector2i(farm.x, farm.y), 3)
	advance(world, 59)
	check(farm.stock == 0 and farm.growth == 59, "crop requires the complete growing period")
	world.step()
	check(farm.stock == 18 and world.metrics.crop_food == 18 and not farm.planted, "ripe crop remains physical stock on the field")
	var stored_before: int = home.food
	WorldEconomy.set_task(world, person, WorldEconomy.task("harvest", Vector2i(farm.x, farm.y), farm.id))
	for i in 40:
		WorldEconomy.execute(world, person, home)
		if person.cargo > 0: break
	check(farm.stock == 12 and person.cargo == 6 and home.food == stored_before, "harvest fills a basket without instantly crediting storage")
	ledger(world, "farming")
	world.paint(Vector2i(farm.x, farm.y), 3, WorldState.Terrain.WATER)
	check(WorldEconomy.building(world, farm.id).is_empty() and person.task.is_empty(), "removing farmland cancels obsolete work")
	check(person.cargo == 6 and person.cargo_kind == "food", "destroying a field preserves already harvested cargo")
	ledger(world, "lost farmland")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null, "edited world with interrupted farming remains loadable")

	world = settlement(1, 48)
	home = world.towns[0]
	person = world.people[0]
	person.cargo = 6
	person.cargo_kind = "food"
	world.metrics.harvested_food += 6
	WorldEconomy.set_task(world, person, WorldEconomy.task("deliver", Vector2i.ZERO))
	WorldEconomy.execute(world, person, home)
	check(home.food == 48 and person.cargo == 6, "a full camp cannot accept more food or delete waiting cargo")
	for i in 19: WorldEconomy.execute(world, person, home)
	check(home.food == 48 and person.cargo == 0 and world.metrics.spoiled_food == 6, "waiting perishables eventually spoil with an accounted loss")
	ledger(world, "full camp")
	WorldEconomy.add_building(world, home, "store", Vector2i(4, 4), true)
	check(WorldEconomy.food_capacity(world, home) == 168 and WorldEconomy.wood_capacity(world, home) == 128, "finished store expands finite capacities")
	var store: Dictionary = world.buildings.back()
	home.food += 120
	home.wood += 100
	world.metrics.spawn_food += 120
	world.metrics.harvested_wood += 100
	world.paint(Vector2i(store.x, store.y), 3, WorldState.Terrain.WATER)
	check(home.food == 48 and home.wood == 48, "destroying a store removes stock that the remaining camp cannot hold")
	ledger(world, "destroyed store")
	check(WorldState.from_dict(world.to_dict()) != null, "destroyed store leaves a valid save")

	world = settlement(1, 30, 6)
	home = world.towns[0]
	person = world.people[0]
	project = WorldEconomy.add_building(world, home, "house", Vector2i(-4, -4))
	WorldEconomy.set_task(world, person, WorldEconomy.task("supply", Vector2i.ZERO, project.id))
	for i in 24:
		WorldEconomy.execute(world, person, home)
		if project.delivered == 6: break
	world.ignite(Vector2i(project.x, project.y), 0)
	world.wet_until = 1000
	advance(world, 12)
	check(WorldEconomy.building(world, project.id).is_empty() and world.metrics.lost_wood == 6, "burning an unfinished project destroys delivered material once")
	ledger(world, "construction fire")
	check(WorldState.from_dict(world.to_dict()) != null, "fire and canceled construction tasks remain loadable")

	world = settlement(2, 10, 6)
	home = world.towns[0]
	project = WorldEconomy.add_building(world, home, "house", Vector2i(-4, -4))
	var broken := world.to_dict()
	broken.buildings.append(broken.buildings[0].duplicate())
	check(WorldState.from_dict(broken) == null, "duplicate building IDs rejected")
	broken = world.to_dict()
	broken.people[0].cargo = 7
	broken.people[0].cargo_kind = "food"
	check(WorldState.from_dict(broken) == null, "oversized cargo rejected")
	broken = world.to_dict()
	broken.buildings[1].delivered = 7
	check(WorldState.from_dict(broken) == null, "project cannot contain more than its required materials")
	WorldEconomy.set_task(world, world.people[0], WorldEconomy.task("build", Vector2i(project.x, project.y), project.id))
	WorldEconomy.set_task(world, world.people[1], WorldEconomy.task("build", Vector2i(project.x, project.y), project.id))
	check(WorldState.from_dict(world.to_dict()) == null, "duplicate exclusive work reservations rejected")
	for p in world.people: WorldEconomy.set_task(world, p, {})
	var legacy := world.to_dict()
	legacy.version = 2
	legacy.erase("buildings")
	legacy.erase("metrics")
	for chunk in legacy.chunks: chunk.erase("wood")
	for p in legacy.people:
		for key in ["name", "rations", "cargo", "cargo_kind", "energy", "job", "task"]: p.erase(key)
	var migrated := WorldState.from_dict(JSON.parse_string(JSON.stringify(legacy)))
	check(migrated != null and migrated.towns[0].food == 10 and migrated.towns[0].wood == 6 and migrated.people.size() == 2, "v2 migration preserves stored supplies and inhabitants")
	check(migrated != null and migrated.people[0].rations == 0 and WorldEconomy.count(migrated, migrated.towns[0], "camp") == 1, "migration creates a camp without granting fresh food")
	check(migrated != null and WorldState.from_dict(migrated.to_dict()) != null, "migrated economy can be saved again in v3")


	world = settlement()
	home = world.towns[0]
	world.paint(Vector2i.ZERO, 14, WorldState.Terrain.WATER)
	world.paint(Vector2i.ZERO, 2, WorldState.Terrain.GRASS)
	world.paint(Vector2i(6, 0), 2, WorldState.Terrain.GRASS)
	home = {"id": world.next_id, "name": "Разделённый берег", "x": 0, "y": 0, "food": 0, "wood": 0, "level": 1}
	world.next_id += 1
	world.towns.append(home)
	WorldEconomy.add_building(world, home, "camp", Vector2i.ZERO, true)
	world.add_person(Vector2i(6, 0), false)
	advance(world, 10)
	check(world.people.back().home == -1 and world.people.back().x >= 4, "people on a disconnected island do not join or travel to a nearby camp")

	for seed_value in [42817, 71, 1024]:
		world = WorldState.new()
		world.generate(seed_value)
		world.populate_demo()
		advance(world, 200)
		ledger(world, "seed %d at day 11" % seed_value)
		var restored := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
		check(restored != null, "seed %d: active work snapshot is valid" % seed_value)
		var footprints_valid := true
		for i in 1000:
			world.step()
			if restored != null: restored.step()
			for p in world.people:
				if not world.walkable(Vector2i(p.x, p.y)): footprints_valid = false
		ledger(world, "seed %d after five years" % seed_value)
		check(world.people.size() >= 6 and footprints_valid, "seed %d: initial population survives with valid routes" % seed_value)
		check(restored != null and JSON.stringify(restored.to_dict()) == JSON.stringify(world.to_dict()), "seed %d: five-year continuation matches after reload" % seed_value)
		if seed_value == 42817:
			check(WorldEconomy.count(world, world.towns[0], "house") > 0 and WorldEconomy.count(world, world.towns[0], "farm") > 0 and WorldEconomy.count(world, world.towns[0], "store") > 0, "demo independently completes housing, a farm and a store")
			check(world.metrics.seed_food > 0 and world.metrics.crop_food > 0, "demo autonomously grows and harvests crops")
	print("Economy: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
