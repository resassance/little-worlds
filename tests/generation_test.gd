extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func food_conserved(world: WorldState) -> bool:
	var stock := 0
	for town in world.towns: stock += town.food
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
	for seed_value in [42817, 71, 1024]:
		var world := WorldState.new()
		world.generate(seed_value)
		world.populate_demo()
		var generation := 1
		var children_never_work := true
		var unrelated_partners := true
		var child_learned := false
		var adult_kept_learning := false
		for i in 100 * WorldLife.YEAR:
			world.step()
			for person in world.people:
				generation = maxi(generation, person.generation)
				if not person.trained_by.is_empty():
					if not WorldLife.adult(world, person): child_learned = true
					else: adult_kept_learning = true
				if not WorldLife.adult(world, person) and (person.cargo != 0 or not person.task.is_empty()): children_never_work = false
				if person.partner != -1 and WorldLife.related(person, WorldLife.person(world, person.partner)): unrelated_partners = false
			if world.ticks % (10 * WorldLife.YEAR) == 0:
				check(food_conserved(world), "seed %d year %d: food conserved through birth, care and death" % [seed_value, world.ticks / WorldLife.YEAR])
				check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null, "seed %d year %d: family checkpoint loads" % [seed_value, world.ticks / WorldLife.YEAR])
		check(world.metrics.births >= 6 and generation >= 3, "seed %d: three generations develop without player assistance" % seed_value)
		check(world.metrics.deaths > 0 and not world.ancestry_archive.is_empty(), "seed %d: mortality records earlier generations" % seed_value)
		check(children_never_work and unrelated_partners, "seed %d: children remain dependent and relatives do not pair" % seed_value)
		check(not world.people.is_empty(), "seed %d: residents survive one century" % seed_value)
		check(world.metrics.lessons > 0 and child_learned and adult_kept_learning, "seed %d: children learn through meetings and retain skills as adults" % seed_value)
		var restored := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
		for i in 5 * WorldLife.YEAR:
			world.step()
			if restored != null: restored.step()
		check(restored != null and JSON.stringify(restored.to_dict()) == JSON.stringify(world.to_dict()), "seed %d: century-old families continue identically after reload" % seed_value)
		print("Seed %d: generation %d, %d births, %d deaths, %d living, %d lessons at year 105." % [seed_value, generation, world.metrics.births, world.metrics.deaths, world.people.size(), world.metrics.lessons])
	print("Generations: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
