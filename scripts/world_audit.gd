class_name WorldAudit
extends RefCounted

static func balances(world) -> Dictionary:
	var food := 0
	var wood := 0
	var materials := WorldCivilization.empty_stock()
	for home in world.towns:
		food += int(home.food)
		wood += int(home.wood)
	for family in world.households: food += int(family.food)
	for value in world.civilization.values():
		for key in materials: materials[key] += int(value.stock[key])
	for building in world.buildings:
		food += int(building.stock)
		if not building.ready: wood += int(building.delivered)
		for key in building.get("materials", {}): materials[key] += int(building.materials[key])
	for member in world.people:
		food += int(member.rations)
		if member.cargo_kind in ["food", "seed"]: food += int(member.cargo)
		elif member.cargo_kind == "wood": wood += int(member.cargo)
		elif materials.has(member.cargo_kind): materials[member.cargo_kind] += int(member.cargo)
	for ship in world.voyages + world.journeys:
		food += int(ship.food)
		if ship.cargo_kind == "food": food += int(ship.cargo)
		elif ship.cargo_kind == "wood": wood += int(ship.cargo)
		elif materials.has(ship.cargo_kind): materials[ship.cargo_kind] += int(ship.cargo)
	for site in world.heritage.sites:
		wood += int(site.wood)
		for key in materials: materials[key] += int(site.stock[key])
	var m: Dictionary = world.metrics
	var result := {"food": int(m.spawn_food + m.harvested_food + m.crop_food) - food - int(m.eaten_food + m.seed_food + m.spoiled_food + m.growth_food + m.lost_food + m.processed_food), "wood": int(m.harvested_wood) - wood - int(m.built_wood + m.growth_wood + m.lost_wood + m.processed_wood)}
	for key in materials: result[key] = int(world.industry.produced[key]) - int(materials[key]) - int(world.industry.consumed[key]) - int(world.industry.lost[key])
	return result

static func conserved(world) -> bool:
	for value in balances(world).values():
		if value != 0: return false
	return true
