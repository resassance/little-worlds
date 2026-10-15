extends "res://tests/economy_test.gd"

func run() -> void:
	var world := settlement(4, 30, 18)
	var home: Dictionary = world.towns[0]
	var building := WorldEconomy.add_building(world, home, "house", Vector2i(-5, -4))
	var first: Dictionary = world.people[0]
	var second: Dictionary = world.people[1]
	for person in [first, second]:
		person.x = home.x; person.y = home.y
	world.workforce.begin(world)
	for i in 100: check(WorldEconomy.in_transit(world, building.id) == 0, "empty delivery index remains exact")
	check(world.workforce.shipment_scans == 1, "repeated queries share a single population scan")
	WorldEconomy.set_task(world, first, WorldEconomy.task("supply", Vector2i.ZERO, building.id))
	WorldEconomy.execute(world, first, home)
	check(first.cargo == 6 and WorldEconomy.in_transit(world, building.id) == 6, "picking up timber immediately updates cached shipment")
	WorldEconomy.set_task(world, second, WorldEconomy.task("supply", Vector2i.ZERO, building.id))
	WorldEconomy.execute(world, second, home)
	check(second.cargo == 0 and home.wood == 12, "another carrier cannot reserve already transported timber")
	for i in 30:
		if first.task.is_empty(): break
		WorldEconomy.execute(world, first, home)
	check(building.delivered == 6 and WorldEconomy.in_transit(world, building.id) == 0, "arrival clears shipment without losing physical materials")
	ledger(world, "indexed delivery")
	var forge := WorldEconomy.add_building(world, home, "forge", Vector2i(5, -5))
	var data := WorldCivilization.ensure(world, home)
	data.stock.stone = 10
	world.industry.produced.stone += 10
	first.x = home.x; first.y = home.y
	WorldEconomy.set_task(world, first, WorldEconomy.task("supply_goods", Vector2i.ZERO, forge.id))
	first.task.resource = "stone"
	check(WorldCivilization.material_in_transit(world, forge.id, "stone") == 0, "uncollected materials are not counted as cargo")
	WorldCivilization.execute(world, first, home)
	check(WorldCivilization.material_in_transit(world, forge.id, "stone") == 6, "material pickup invalidates shipment cache")
	check(WorldEconomy.in_transit(world, forge.id) == 0, "stone delivery cannot count as timber")
	WorldEconomy.set_task(world, first, {})
	check(WorldCivilization.material_in_transit(world, forge.id, "stone") == 0 and first.cargo == 6, "cancelled supply keeps cargo but releases building reservation")
	WorldEconomy.set_task(world, first, WorldEconomy.task("supply_goods", Vector2i.ZERO, forge.id))
	first.task.resource = "stone"
	check(WorldCivilization.material_in_transit(world, forge.id, "stone") == 6, "loaded reassignment counts existing cargo")
	world.remove_person(world.people.find(first), "проверка")
	check(WorldCivilization.material_in_transit(world, forge.id, "stone") == 0, "carrier death releases material reservation")
	world.workforce.end()
	var loaded := WorldState.from_dict(world.to_dict())
	check(loaded != null and WorldCivilization.material_in_transit(loaded, forge.id, "stone") == 0, "delivery cache is rebuilt from actual saved people")
	var options := {"courtship": true, "sex": "male"}
	world.population.active = false; world.population.ready = false
	var plain := world.population.nearby(world, Vector2i.ZERO, 200, home.id, options)
	world.population.active = true
	world.population.rebuild(world)
	var indexed := world.population.nearby(world, Vector2i.ZERO, 200, home.id, options)
	check(plain == indexed, "courtship filtering preserves candidate order with and without spatial index")
	for person in indexed: check(person.sex == "female" and person.partner == -1 and person.courting == -1, "courtship query excludes incompatible candidates")
	print("Workforce delivery: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
