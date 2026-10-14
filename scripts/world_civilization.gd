class_name WorldCivilization
extends RefCounted

const GOODS := {"stone": "Камень", "ore": "Руда", "pottery": "Керамика", "cloth": "Ткань", "metal": "Металл", "tools": "Инструменты"}
const CAPACITY := 96
const EXTRA := {"kiln": {"stone": 4}, "loom": {"stone": 2}, "forge": {"stone": 6}, "market": {"stone": 4}, "school": {"stone": 6}, "council": {"stone": 8}, "port": {"stone": 6, "cloth": 4}}
const RECIPES := {
	"pottery": {"building": "kiln", "tech": "ceramics", "inputs": {"stone": 2, "wood": 1}, "yield": 2, "work": 8},
	"cloth": {"building": "loom", "tech": "weaving", "inputs": {"food": 1}, "yield": 2, "work": 8},
	"metal": {"building": "forge", "tech": "metallurgy", "inputs": {"ore": 2, "wood": 1}, "yield": 1, "work": 10},
	"tools": {"building": "forge", "tech": "metallurgy", "inputs": {"metal": 1, "wood": 1}, "yield": 1, "work": 8}
}

static func empty_stock() -> Dictionary:
	var result := {}
	for key in GOODS: result[key] = 0
	return result

static func ensure(world, home: Dictionary) -> Dictionary:
	if not world.civilization.has(home.id): world.civilization[home.id] = {"town": int(home.id), "stock": empty_stock(), "leader": -1, "tool_wear": 0}
	return world.civilization[home.id]

static func get_data(world, id: int) -> Dictionary:
	return world.civilization.get(id, {})

static func inputs_available(world, home: Dictionary, inputs: Dictionary) -> bool:
	var stock: Dictionary = ensure(world, home).stock
	for key in inputs:
		if int(home[key] if key in ["food", "wood"] else stock[key]) < int(inputs[key]): return false
	return true

static func consume(world, home: Dictionary, inputs: Dictionary) -> void:
	var stock: Dictionary = ensure(world, home).stock
	for key in inputs:
		if key in ["food", "wood"]:
			home[key] -= int(inputs[key])
			world.metrics["processed_" + key] += int(inputs[key])
		else:
			stock[key] -= int(inputs[key])
			world.industry.consumed[key] += int(inputs[key])

static func material_defaults(value: Dictionary) -> void:
	value.materials = {}
	for key in EXTRA.get(value.kind, {}): value.materials[key] = int(EXTRA[value.kind][key]) if value.ready else 0

static func materials_ready(value: Dictionary) -> bool:
	for key in EXTRA.get(value.kind, {}):
		if int(value.get("materials", {}).get(key, 0)) < int(EXTRA[value.kind][key]): return false
	return true

static func material_in_transit(world, id: int, kind: String) -> int:
	var amount := 0
	var value := WorldEconomy.building(world, id)
	if value.is_empty(): return 0
	for member in WorldEconomy.members(world, WorldEconomy.town(world, value.town)):
		if member.task.get("kind", "") == "supply_goods" and member.task.building == id and member.cargo_kind == kind: amount += int(member.cargo)
	return amount

static func supply_assign(world, member: Dictionary, home: Dictionary, value: Dictionary) -> bool:
	var stock: Dictionary = ensure(world, home).stock
	for key in EXTRA.get(value.kind, {}):
		var missing: int = int(EXTRA[value.kind][key]) - int(value.materials[key]) - material_in_transit(world, value.id, key)
		if missing <= 0 or stock[key] <= 0: continue
		WorldEconomy.set_task(world, member, WorldEconomy.task("supply_goods", Vector2i(home.x, home.y), value.id))
		member.task.resource = key
		member.job = "builder"
		return true
	return false

static func assign(world, member: Dictionary, home: Dictionary) -> bool:
	if WorldEconomy.food_days(world, home) < 6 or member.energy < 35: return false
	var data := ensure(world, home)
	if member.skills.build < 10: return false
	var need_ore: bool = data.stock.ore < 12 and WorldEconomy.count(world, home, "forge", false) > 0
	if data.stock.stone < 24 or need_ore:
		for deposit in WorldEconomy.navigation(world,home).quarries:
			var point: Vector2i=deposit.land
			var rock: Vector2i=deposit.rock
			if world.fires.has(point) or world.mineral_deposits.get(rock,36)<=0 or world.claims.has("quarry:%d:%d" % [point.x,point.y]): continue
			WorldEconomy.set_task(world, member, WorldEconomy.task("quarry", point))
			member.task.rock_x=rock.x; member.task.rock_y=rock.y
			member.task.resource="ore" if need_ore and data.stock.stone>=8 else "stone"
			member.job="miner"
			return true
	for key in RECIPES:
		var recipe: Dictionary = RECIPES[key]
		if data.stock[key] >= (8 if key == "tools" else 12) or not WorldSociety.active(world, home, recipe.tech) or not inputs_available(world, home, recipe.inputs): continue
		for building in world.workforce.buildings(world, home):
			if building.town != home.id or not building.ready or building.kind != recipe.building: continue
			if world.claims.has("manufacture:%d" % building.id): continue
			WorldEconomy.set_task(world, member, WorldEconomy.task("manufacture", Vector2i(building.x, building.y), building.id))
			member.task.resource = key
			member.task.started = false
			member.job = "artisan"
			return true
	return false

static func execute(world, member: Dictionary, home: Dictionary) -> bool:
	var task: Dictionary = member.task
	if task.kind not in ["quarry", "manufacture", "supply_goods"] and not (task.kind == "deliver" and GOODS.has(member.cargo_kind)): return false
	var target := Vector2i(task.x, task.y)
	var building := WorldEconomy.building(world, task.building)
	if task.kind == "supply_goods" and member.cargo > 0 and not building.is_empty(): target = Vector2i(building.x, building.y)
	if world.fires.has(target) or not world.walkable(target) or not WorldEconomy.navigation(world, home).parents.has(target) or (task.kind in ["manufacture", "supply_goods"] and building.is_empty()):
		WorldEconomy.set_task(world, member, {})
		return true
	if not WorldEconomy.move(world, member, target, home): return true
	var data := ensure(world, home)
	if task.kind == "deliver":
		var amount: int = mini(member.cargo, CAPACITY - int(data.stock[member.cargo_kind]))
		data.stock[member.cargo_kind] += amount
		member.cargo -= amount
		if member.cargo == 0:
			member.cargo_kind = ""
			WorldEconomy.set_task(world, member, {})
		return true
	if task.kind == "supply_goods":
		var key: String = task.resource
		if member.cargo == 0:
			var missing: int = int(EXTRA[building.kind][key]) - int(building.materials[key]) - material_in_transit(world, building.id, key)
			var amount: int = mini(WorldEconomy.LOAD, mini(int(data.stock[key]), missing))
			if amount <= 0: WorldEconomy.set_task(world, member, {})
			else:
				data.stock[key] -= amount
				member.cargo = amount
				member.cargo_kind = key
		else:
			building.materials[key] += member.cargo
			member.cargo = 0
			member.cargo_kind = ""
			WorldEconomy.set_task(world, member, {})
		return true
	if WorldLife.years(world, member) >= 60 and (world.ticks + int(member.id)) % 2: return true
	if task.kind == "quarry":
		var rock := Vector2i(task.rock_x, task.rock_y)
		if world.terrain_at(rock) != WorldState.Terrain.MOUNTAIN or world.mineral_deposits.get(rock, 36) <= 0:
			WorldEconomy.set_task(world, member, {})
			return true
		task.work += WorldSocial.work_credit(world, member, "build")
		WorldSocial.practice(world, member, "build")
		if task.work < 6: return true
		var amount: int = mini(3, world.mineral_deposits.get(rock, 36))
		world.mineral_deposits[rock] = int(world.mineral_deposits.get(rock, 36)) - amount
		if world.mineral_deposits[rock] == 0 or int(world.mineral_deposits[rock])/12 != (int(world.mineral_deposits[rock])+amount)/12 or not world.landscape.site_regions.get(WorldState.chunk_of(rock),{}).has(rock): world.landscape.site(rock,"quarry")
		member.cargo = amount
		member.cargo_kind = task.resource
		world.industry.produced[task.resource] += amount
		if WorldSociety.active(world, home, "stonework"): WorldSociety.use(world, home, "stonework", member)
		WorldEconomy.set_task(world, member, {})
		return true
	var recipe: Dictionary = RECIPES[task.resource]
	if not WorldSociety.active(world, home, recipe.tech):
		WorldEconomy.set_task(world, member, {})
		return true
	if not task.started:
		if not inputs_available(world, home, recipe.inputs):
			WorldEconomy.set_task(world, member, {})
			return true
		consume(world, home, recipe.inputs)
		task.started = true
	task.work += WorldSocial.work_credit(world, member, "build")
	member.energy = maxf(0, member.energy - 0.5)
	WorldSocial.practice(world, member, "build")
	if task.work < int(recipe.work): return true
	member.cargo = int(recipe.yield)
	member.cargo_kind = task.resource
	world.industry.produced[task.resource] += int(recipe.yield)
	WorldSociety.use(world, home, recipe.tech, member)
	WorldEconomy.set_task(world, member, {})
	return true

static func plan(world, home: Dictionary) -> void:
	var job := WorldConstructionPlanJob.new(world, home, true)
	while not job.finished: job.unit()

static func tool_credit(world, member: Dictionary, home: Dictionary) -> int:
	var data := ensure(world, home)
	if data.stock.tools <= 0 or (world.ticks + int(member.id)) % 4 != 0: return 0
	data.tool_wear += 1
	if data.tool_wear >= 40:
		data.stock.tools -= 1
		world.industry.consumed.tools += 1
		data.tool_wear = 0
	return 1

static func daily(world) -> void:
	for home in world.towns: daily_town(world, home)

static func daily_town(world, home: Dictionary) -> void:
	var data := ensure(world, home)
	if WorldEconomy.count(world, home, "council") == 0: return
	var leader := -1
	var best := -1
	for member in WorldEconomy.members(world, home):
		if not WorldLife.adult(world, member): continue
		var score: int = int(member.skills.food) + int(member.skills.build) + WorldLife.years(world, member)
		if score > best:
			best = score
			leader = int(member.id)
	if data.leader != leader:
		data.leader = leader
		if leader != -1: world.log_event("Совет поселения", "%s: старейшина — %s." % [home.name, WorldLife.label(world, leader)])
	if leader != -1: WorldSociety.use(world, home, "governance")

static func lost_building(world, value: Dictionary) -> void:
	for key in value.get("materials", {}): world.industry.lost[key] += int(value.materials[key])

static func reconcile(world) -> void:
	for id in world.civilization.keys():
		if not WorldEconomy.town(world, id).is_empty(): continue
		for key in GOODS: world.industry.lost[key] += int(world.civilization[id].stock[key])
		world.civilization.erase(id)
	for home in world.towns: ensure(world, home)

static func description(world, home: Dictionary) -> String:
	var data := ensure(world, home)
	var text := "\n\nМатериалы и ремёсла"
	for key in GOODS: text += "\n%s: %d" % [GOODS[key], data.stock[key]]
	if data.leader != -1: text += "\nСтарейшина: " + WorldLife.label(world, data.leader)
	return text

static func save(world) -> Dictionary:
	var deposits: Array = []
	for cell in world.mineral_deposits: deposits.append([cell.x, cell.y, world.mineral_deposits[cell]])
	return {"towns": world.civilization.values().duplicate(true), "metrics": world.industry.duplicate(true), "deposits": deposits}

static func restore(world, data: Variant) -> bool:
	if not data is Dictionary or not data.get("towns") is Array or data.towns.size() != world.towns.size() or not data.get("metrics") is Dictionary: return false
	for category in ["produced", "consumed", "lost"]:
		if not valid_stock(data.metrics.get(category), 100000000): return false
		world.industry[category] = data.metrics[category].duplicate()
		for key in GOODS: world.industry[category][key] = int(world.industry[category][key])
	for item in data.towns:
		if not item is Dictionary or not WorldState._integer(item.get("town")) or WorldEconomy.town(world, item.town).is_empty() or world.civilization.has(int(item.town)): return false
		if not valid_stock(item.get("stock"), CAPACITY) or not WorldState._integer(item.get("leader")) or not WorldState._integer(item.get("tool_wear")) or item.tool_wear < 0 or item.tool_wear >= 40: return false
		var value: Dictionary = item.duplicate(true)
		for key in ["town", "leader", "tool_wear"]: value[key] = int(value[key])
		for key in GOODS: value.stock[key] = int(value.stock[key])
		world.civilization[value.town] = value
	if not data.get("deposits") is Array or data.deposits.size() > 65536: return false
	for item in data.deposits:
		if not item is Array or item.size() != 3: return false
		for number in item:
			if not WorldState._integer(number): return false
		var cell := Vector2i(item[0], item[1])
		if not world.inside(cell) or world.mineral_deposits.has(cell) or item[2] < 0 or item[2] > 36: return false
		world.mineral_deposits[cell] = int(item[2])
	for building in world.buildings:
		if not building.get("materials") is Dictionary: return false
		var required: Dictionary = EXTRA.get(building.kind, {})
		if building.materials.size() != required.size(): return false
		for key in required:
			if not WorldState._integer(building.materials.get(key)) or building.materials[key] < 0 or building.materials[key] + material_in_transit(world, building.id, key) > required[key]: return false
			building.materials[key] = int(building.materials[key])
			if building.ready and building.materials[key] != int(required[key]): return false
	for member in world.people:
		var task: Dictionary = member.task
		if task.get("kind", "") not in ["quarry", "manufacture", "supply_goods"]: continue
		if not task.get("resource") is String: return false
		if task.kind == "quarry":
			if task.resource not in ["stone", "ore"] or not WorldState._integer(task.get("rock_x")) or not WorldState._integer(task.get("rock_y")): return false
			var rock := Vector2i(task.rock_x, task.rock_y)
			if rock.distance_to(Vector2i(task.x, task.y)) != 1 or world.terrain_at(rock) != WorldState.Terrain.MOUNTAIN: return false
		elif task.kind == "manufacture":
			var building := WorldEconomy.building(world, task.building)
			if not RECIPES.has(task.resource) or not task.get("started") is bool or building.is_empty() or not building.ready or building.kind != RECIPES[task.resource].building or building.town != member.home: return false
		else:
			var building := WorldEconomy.building(world, task.building)
			if building.is_empty() or building.ready or building.town != member.home or not EXTRA.get(building.kind, {}).has(task.resource) or (member.cargo > 0 and member.cargo_kind != task.resource): return false
	return true

static func valid_stock(value: Variant, limit: int) -> bool:
	if not value is Dictionary or value.size() != GOODS.size(): return false
	for key in GOODS:
		if not WorldState._integer(value.get(key)) or value[key] < 0 or value[key] > limit: return false
	return true
