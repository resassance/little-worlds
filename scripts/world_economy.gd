class_name WorldEconomy
extends RefCounted


const DAY_TICKS := 20
const DAYS_PER_YEAR := 12
const HUNGER_PER_STEP := 0.5
const NUTRITION := 20.0
const LOAD := 6
const RANGE := 24
const COST := {"camp": 0, "house": 6, "farm": 4, "store": 12, "workshop": 12, "archive": 16, "kiln": 8, "loom": 8, "forge": 12, "market": 10, "school": 16, "council": 16, "dock": 10, "port": 20, "boat": 8, "sailboat": 24}
const WORK := {"camp": 0, "house": 16, "farm": 12, "store": 24, "workshop": 28, "archive": 32, "kiln": 24, "loom": 24, "forge": 32, "market": 28, "school": 36, "council": 36, "dock": 24, "port": 40, "boat": 24, "sailboat": 48}
const SIZE := {"camp": 1, "house": 2, "farm": 3, "store": 3, "workshop": 2, "archive": 2, "kiln": 2, "loom": 2, "forge": 2, "market": 2, "school": 2, "council": 2, "dock": 2, "port": 3, "boat": 1, "sailboat": 2}
const NAMES := {"camp": "Лагерь", "house": "Дом", "farm": "Поле", "store": "Склад", "workshop": "Мастерская", "archive": "Архив", "kiln": "Гончарная печь", "loom": "Ткацкая", "forge": "Кузница", "market": "Рынок", "school": "Школа", "council": "Совет", "dock": "Причал", "port": "Порт", "boat": "Лодка", "sailboat": "Парусник"}
const JOBS := {"settler": "Поселенец", "forager": "Собиратель", "logger": "Лесоруб", "builder": "Строитель", "farmer": "Земледелец", "child": "Ребёнок", "teen": "Подросток", "carer": "Опекун", "teacher": "Наставник", "researcher": "Исследователь", "miner": "Каменотёс", "artisan": "Ремесленник", "fisher": "Рыбак", "sailor": "Мореплаватель", "merchant": "Торговец"}
const TASKS := {"gather_food": "Собирает еду", "gather_wood": "Заготавливает древесину", "deliver": "Несёт груз в лагерь", "supply": "Доставляет материалы", "build": "Строит", "plant": "Засевает поле", "harvest": "Собирает урожай", "eat": "Идёт за едой", "rest": "Отдыхает", "care": "Заботится о ребёнке", "visit": "Идёт общаться", "teach": "Обучает ремеслу", "research": "Осваивает технологию", "quarry": "Добывает камень и руду", "manufacture": "Работает в мастерской", "supply_goods": "Доставляет материалы", "fish": "Ловит рыбу", "travel": "Путешествует"}
const METRICS := ["spawn_food", "harvested_food", "harvested_wood", "delivered_food", "delivered_wood", "eaten_food", "seed_food", "crop_food", "spoiled_food", "built_wood", "growth_food", "growth_wood", "lost_food", "lost_wood", "births", "deaths", "helped_food", "lessons", "research_work", "discoveries", "processed_food", "processed_wood"]

static func person_defaults(world, person: Dictionary) -> void:
	var names := ["Мира", "Иван", "Лада", "Тимур", "Яна", "Роман", "Ася", "Марк", "Ника", "Лев", "Вера", "Илья"]
	person.name = "%s %d" % [names[posmod(world.world_seed + int(person.id), names.size())], person.id]
	person.rations = 2
	person.cargo = 0
	person.cargo_kind = ""
	person.energy = 100.0
	person.job = "settler"
	person.task = {}

static func task(kind: String, cell: Vector2i, building: int = -1) -> Dictionary:
	return {"kind": kind, "x": cell.x, "y": cell.y, "building": building, "work": 0}

static func town(world, id: int) -> Dictionary:
	return world.population.town(world, id)

static func building(world, id: int) -> Dictionary:
	return world.building_index.get(id, {})

static func footprint(value: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(value.x, value.y), Vector2i.ONE * int(SIZE[value.kind]))

static func at(world, cell: Vector2i) -> Dictionary:
	return world.occupied.get(cell, {})

static func navigation(world, home: Dictionary) -> Dictionary:
	if world.navigation.has(home.id): return world.navigation[home.id]
	var job := WorldNavigationJob.new(world, home)
	job.advance(0)
	return job.result

static func move(world, person: Dictionary, target: Vector2i, home: Dictionary) -> bool:
	var current := Vector2i(person.x, person.y)
	if current == target: return true
	var nav: Dictionary = navigation(world, home)
	var parents: Dictionary = nav.parents
	if not parents.has(current) or not parents.has(target): return false
	if not nav.routes.has(target):
		if nav.routes.size() >= 64: nav.routes.erase(nav.routes.keys()[0])
		var route := {}
		var cursor := target
		var root := Vector2i(home.x, home.y)
		while cursor != root:
			route[parents[cursor]] = cursor
			cursor = parents[cursor]
		nav.routes[target] = route
	var next: Vector2i = nav.routes[target].get(current, parents[current])
	if next == current or world.fires.has(next): return false
	person.x = next.x
	person.y = next.y
	world.track_person_move(person, current)
	person.energy = maxf(0, person.energy - 0.25)
	return next == target

static func members(world, home: Dictionary) -> Array[Dictionary]:
	if world.population_dirty:
		world.population_index.clear()
		for person in world.people:
			if not world.population_index.has(person.home):
				var residents: Array[Dictionary] = []
				world.population_index[person.home] = residents
			world.population_index[person.home].append(person)
		world.population_dirty = false
	if not world.population_index.has(home.id):
		var empty: Array[Dictionary] = []
		world.population_index[home.id] = empty
	return world.population_index[home.id]

static func count(world, home: Dictionary, kind: String, ready_only: bool = true) -> int:
	if home.is_empty(): return 0
	var result := 0
	for value in world.workforce.buildings(world, home):
		if value.town == home.id and value.kind == kind and (value.ready or not ready_only): result += 1
	return result

static func food_capacity(world, home: Dictionary) -> int:
	return 48 + count(world, home, "store") * 120

static func wood_capacity(world, home: Dictionary) -> int:
	return 48 + count(world, home, "store") * 80

static func housing(world, home: Dictionary) -> int:
	return 4 + count(world, home, "house") * 4

static func food_days(world, home: Dictionary) -> float:
	if world.workforce.active: return world.workforce.food_days(world, home)
	return float(home.food) / maxf(0.25, daily_need(world, home))

static func daily_need(world, home: Dictionary) -> float:
	if world.workforce.active: return world.workforce.daily_need(world, home)
	var daily_need := 0.0
	for person in members(world, home): daily_need += WorldLife.hunger_rate(world, person) * DAY_TICKS / NUTRITION
	return daily_need

static func storage_pressure(world, home: Dictionary) -> bool:
	var capacity := food_capacity(world, home)


	return capacity < daily_need(world, home) * 12.0 and home.food >= ceili(capacity * 0.75)

static func in_transit(world, id: int) -> int:
	var result := 0
	var value := building(world, id)
	if value.is_empty(): return 0
	for person in members(world, town(world, value.town)):
		if not person.task.is_empty() and person.task.kind == "supply" and person.task.building == id and person.cargo_kind == "wood": result += person.cargo
	return result

static func available_wood(world, home: Dictionary) -> int:
	var reserved := 0
	for value in world.workforce.buildings(world, home):
		if value.town == home.id and not value.ready:
			reserved += maxi(0, int(COST[value.kind]) - int(value.delivered) - in_transit(world, value.id))
	return maxi(0, int(home.wood) - reserved)

static func add_building(world, home: Dictionary, kind: String, cell: Vector2i, ready: bool = false) -> Dictionary:
	if world.buildings.size() >= WorldState.MAX_BUILDINGS: return {}
	WorldSociety.ensure_town(world, home)
	var value := {"id": world.next_id, "town": home.id, "kind": kind, "x": cell.x, "y": cell.y,
		"ready": ready, "delivered": int(COST[kind]) if ready else 0, "work": int(WORK[kind]) if ready else 0, "growth": 0, "stock": 0, "planted": false, "integrity": 12}
	world.next_id += 1
	world.buildings.append(value)
	world.workforce.building_added(value)
	WorldCivilization.material_defaults(value)
	WorldCivilization.ensure(world, home)
	world.building_index[value.id] = value
	var rect := footprint(value)
	for y in rect.size.y:
		for x in rect.size.x: world.occupied[rect.position + Vector2i(x, y)] = value
	world.touch_terrain(cell, int(SIZE[kind]))
	return value

static func site(world, home: Dictionary, kind: String) -> Vector2i:
	var center := Vector2i(home.x, home.y)
	var parents: Dictionary = navigation(world, home).parents
	for radius in range(3, 16):
		for direction in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = center + direction * radius
			if valid_site(world, parents, kind, cell): return cell

	for cell in navigation(world, home).cells:
		if absi(cell.x - center.x) + absi(cell.y - center.y) < 3: continue
		if valid_site(world, parents, kind, cell): return cell
	return WorldState.NO_CELL

static func valid_site(world, parents: Dictionary, kind: String, cell: Vector2i) -> bool:
	var dim: int = SIZE[kind]
	if kind in ["dock", "port", "boat", "sailboat"]:
		var shore := false
		for y in range(-1, dim + 1):
			for x in range(-1, dim + 1):
				if world.terrain_at(cell + Vector2i(x, y)) == WorldState.Terrain.WATER: shore = true
		if not shore: return false
	for y in dim:
		for x in dim:
			var point := cell + Vector2i(x, y)
			var ground: int = world.terrain_at(point)
			if not parents.has(point) or world.fires.has(point) or ground not in ([WorldState.Terrain.GRASS] if kind == "farm" else [WorldState.Terrain.GRASS, WorldState.Terrain.SAND]): return false
	for y in range(-1, dim + 1):
		for x in range(-1, dim + 1):
			if world.occupied.has(cell + Vector2i(x, y)): return false
	return true

static func plan(world, home: Dictionary) -> void:
	var residents := members(world, home)
	if residents.is_empty(): return
	var expand_storage := storage_pressure(world, home)
	home.level = 3 if count(world, home, "store") > 0 and count(world, home, "farm") > 0 else (2 if count(world, home, "house") > 0 else 1)
	for value in world.workforce.buildings(world, home):
		if value.town == home.id and not value.ready and (not expand_storage or value.kind == "store"): return
	if food_days(world, home) < 2 and not expand_storage: return
	var kind := ""
	if expand_storage: kind = "store"
	elif housing(world, home) < residents.size() + 1: kind = "house"
	elif count(world, home, "farm", false) < maxi(1, ceili(residents.size() / 12.0)) and site(world, home, "farm") != WorldState.NO_CELL: kind = "farm"
	elif count(world, home, "store", false) == 0: kind = "store"
	elif WorldLife.needs_home(world, home): kind = "house"
	elif WorldSociety.mastered(world, home, "carpentry") and count(world, home, "workshop", false) == 0: kind = "workshop"
	elif WorldSociety.mastered(world, home, "records") and count(world, home, "archive", false) == 0: kind = "archive"
	if kind.is_empty():
		WorldCivilization.plan(world, home)
		return
	if available_wood(world, home) < int(COST[kind]): return
	var cell := site(world, home, kind)
	if cell == WorldState.NO_CELL: return
	if not add_building(world, home, kind, cell).is_empty():
		world.log_event("Начата стройка", "%s: %s. Материалы доставят жители." % [home.name, NAMES[kind].to_lower()])

static func claim_key(value: Dictionary) -> String:
	if value.kind == "fish": return "fish:%d:%d" % [value.x, value.y]
	if value.kind == "quarry": return "quarry:%d:%d" % [value.x, value.y]
	if value.kind == "manufacture": return "manufacture:%d" % value.building
	if value.kind in ["gather_food", "gather_wood"]: return "%s:%d:%d" % [value.kind, value.x, value.y]
	if value.kind in ["build", "plant", "harvest"]: return "%s:%d" % [value.kind, value.building]
	return ""

static func set_task(world, person: Dictionary, value: Dictionary) -> void:
	if person.task.get("kind", "") == "research": WorldSociety.stop(world, person)
	if person.task.get("kind", "") == "teach" and value.get("kind", "") != "teach":
		var student := WorldLife.person(world, person.task.get("dependent", -1))
		if not student.is_empty() and student.get("lesson", {}).get("mentor", -1) == person.id: student.lesson = {}
	if not person.task.is_empty():
		var old_key := claim_key(person.task)
		if world.claims.get(old_key, -1) == person.id: world.claims.erase(old_key)
	person.task = value
	if person.cargo_kind == "seed" and (value.is_empty() or value.kind != "plant"): person.cargo_kind = "food"
	if not value.is_empty():
		var key := claim_key(value)
		if not key.is_empty(): world.claims[key] = person.id
	world.workforce.task_changed(world, person)

static func resource(world, person: Dictionary, home: Dictionary, kind: String) -> Vector2i:
	if world.workforce.active: return world.workforce.resource(world, person, home, kind)
	var candidates: Array[Vector2i] = navigation(world, home)[kind]
	var best := WorldState.NO_CELL
	var best_score := INF
	var found := 0
	var current := Vector2i(person.x, person.y)
	for cell in candidates:
		var key := "%s:%d:%d" % ["gather_food" if kind == "food" else "gather_wood", cell.x, cell.y]
		if world.claims.has(key) or world.fires.has(cell) or not at(world, cell).is_empty(): continue
		var amount: int = world.food_at(cell) if kind == "food" else world.wood_at(cell)
		if amount == 0: continue
		var score := current.distance_squared_to(cell)
		if score < best_score:
			best_score = score
			best = cell
		found += 1
		if found >= 16: break
	return best

static func assign(world, person: Dictionary, home: Dictionary) -> void:
	var center := Vector2i(home.x, home.y)
	if person.cargo > 0:
		if person.cargo_kind == "seed": person.cargo_kind = "food"
		set_task(world, person, task("deliver", center))
		return
	if person.hunger >= 35 and person.rations == 0 and home.food > 0:
		set_task(world, person, task("eat", center))
		return
	if WorldLife.assign_care(world, person, home): return
	var family := WorldLife.household(world, person.household)
	var own_shelter := WorldLife.dwelling_cell(world, family) if not family.is_empty() else WorldState.NO_CELL
	if person.birth_due >= 0 and world.ticks >= person.birth_due - DAY_TICKS and own_shelter != WorldState.NO_CELL:
		set_task(world, person, task("rest", own_shelter))
		return
	if person.energy < 18:
		var resting := center
		if own_shelter != WorldState.NO_CELL: resting = own_shelter
		for value in world.workforce.buildings(world, home):
			if own_shelter != WorldState.NO_CELL: break
			if value.town == home.id and value.kind == "house" and value.ready:
				resting = Vector2i(value.x + 1, value.y + 1)
				break
		set_task(world, person, task("rest", resting))
		return
	if person.social_need >= 55 - int(person.traits.sociability) * 10 and food_days(world, home) >= 6:
		set_task(world, person, task("visit", WorldSocial.visit_target(world, person, home)))
		return
	var plan: Dictionary = world.workforce.context(world, home)
	var population: int = plan.population
	var food_workers: int = plan.food_workers
	var wood_workers: int = plan.wood_workers

	for value in world.workforce.buildings(world, home):
		if value.town != home.id or value.kind != "farm" or not value.ready: continue
		if not WorldSocial.preferred(world, person, home, "farm"): continue
		var cell := Vector2i(value.x, value.y)
		if value.stock > 0 and home.food < food_capacity(world, home) - LOAD and not world.claims.has("harvest:%d" % value.id):
			person.job = "farmer"
			set_task(world, person, task("harvest", cell, value.id))
			return
		if not value.planted and value.stock == 0 and home.food > 2 and not world.claims.has("plant:%d" % value.id) and food_workers >= 1:
			person.job = "farmer"
			set_task(world, person, task("plant", cell, value.id))
			return
	var urgent_food := food_days(world, home) < 6
	if food_workers < maxi(1, ceili(population * 0.5)) and urgent_food:
		if WorldMaritime.fish_assign(world, person, home): return
		var cell := resource(world, person, home, "food")
		if cell != WorldState.NO_CELL:
			person.job = "forager"
			set_task(world, person, task("gather_food", cell))
			return

	if wood_workers == 0 and home.wood < 24 and food_workers > 0 and WorldSocial.preferred(world, person, home, "wood"):
		var cell := resource(world, person, home, "wood")
		if cell != WorldState.NO_CELL:
			person.job = "logger"
			set_task(world, person, task("gather_wood", cell))
			return
	var stocked := food_days(world, home) >= 2
	if stocked or storage_pressure(world, home):
		for value in world.workforce.buildings(world, home):
			if value.town != home.id or value.ready: continue
			if not stocked and value.kind != "store": continue
			if not WorldSocial.preferred(world, person, home, "build"): continue
			var cell := Vector2i(value.x, value.y)
			if WorldCivilization.supply_assign(world, person, home, value): return
			var missing := int(COST[value.kind]) - int(value.delivered) - in_transit(world, value.id)
			if missing > 0 and home.wood > 0:

				person.job = "builder"
				set_task(world, person, task("supply", center, value.id))
				return
			if value.delivered == int(COST[value.kind]) and WorldCivilization.materials_ready(value) and not world.claims.has("build:%d" % value.id):
				person.job = "builder"
				set_task(world, person, task("build", cell, value.id))
				return
	if WorldSociety.research_assign(world, person, home): return
	if WorldCivilization.assign(world, person, home): return
	if home.food < food_capacity(world, home) - LOAD:
		var cell := resource(world, person, home, "food")
		if cell != WorldState.NO_CELL:
			person.job = "forager"
			set_task(world, person, task("gather_food", cell))
			return
	var resting := center
	if person.energy >= 95 and posmod(world.ticks + int(person.id), DAY_TICKS) < 4:
		set_task(world, person, task("visit", center))
		return
	if own_shelter != WorldState.NO_CELL: resting = own_shelter
	for value in world.workforce.buildings(world, home):
		if own_shelter != WorldState.NO_CELL: break
		if value.town == home.id and value.kind == "house" and value.ready:
			resting = Vector2i(value.x + 1, value.y + 1)
			break
	set_task(world, person, task("rest", resting))

static func execute(world, person: Dictionary, home: Dictionary) -> void:
	if person.task.is_empty(): assign(world, person, home)
	if person.task.is_empty(): return
	var active: Dictionary = person.task
	if active.kind == "fish":
		WorldMaritime.fish(world, person, home)
		return
	if WorldCivilization.execute(world, person, home): return
	if active.kind == "research":
		WorldSociety.research(world, person, home)
		return
	if active.kind == "teach":
		WorldSocial.teach(world, person, home)
		return
	if active.kind == "care":
		WorldLife.perform_care(world, person, home)
		return
	var target := Vector2i(active.x, active.y)
	var value := building(world, active.building)
	if world.fires.has(target) or not world.walkable(target) or not navigation(world, home).parents.has(target):
		set_task(world, person, {})
		return
	if active.kind in ["supply", "build", "plant", "harvest"] and value.is_empty():
		set_task(world, person, {})
		return
	if active.kind == "plant" and person.cargo_kind != "seed": return
	if active.kind == "supply" and person.cargo > 0: target = Vector2i(value.x, value.y)
	if not move(world, person, target, home): return
	if WorldLife.years(world, person) >= 60 and active.kind in ["gather_food", "gather_wood", "build", "plant", "harvest"] and (world.ticks + int(person.id)) % 2: return
	if (active.kind == "gather_food" and world.food_at(target) == 0) or (active.kind == "gather_wood" and world.wood_at(target) == 0) or (active.kind == "build" and value.delivered < int(COST[value.kind])) or (active.kind == "plant" and value.planted) or (active.kind == "harvest" and value.stock == 0):
		set_task(world, person, {})
		return
	var skill := WorldSocial.task_skill(active.kind)
	var credit := 1
	if not skill.is_empty():
		credit = WorldSocial.work_credit(world, person, skill)
		WorldSocial.practice(world, person, skill)
		credit += WorldCivilization.tool_credit(world, person, home)
		if skill in ["build", "wood"] and (world.ticks + int(person.id)) % 4 == 0 and WorldSociety.active(world, home, "carpentry"):
			credit += 1
			WorldSociety.use(world, home, "carpentry", person)
	active.work += credit
	match active.kind:
		"gather_food", "gather_wood":
			if active.work < 4: return
			var amount: int = mini(LOAD, world.food_at(target)) if active.kind == "gather_food" else mini(3, world.wood_at(target))
			if amount > 0:
				person.cargo_kind = "food" if active.kind == "gather_food" else "wood"
				person.cargo = amount
				if person.cargo_kind == "food": world._set_food(target, world.food_at(target) - amount)
				else: world.harvest_wood(target, amount)
				world.metrics["harvested_" + person.cargo_kind] += amount
			set_task(world, person, {})
		"deliver":
			var room: int = (food_capacity(world, home) if person.cargo_kind == "food" else wood_capacity(world, home)) - int(home[person.cargo_kind])
			var amount := mini(person.cargo, maxi(0, room))
			home[person.cargo_kind] += amount
			world.metrics["delivered_" + person.cargo_kind] += amount
			person.cargo -= amount
			if person.cargo == 0: person.cargo_kind = ""

			if person.cargo > 0:
				person.energy = minf(100, person.energy + 1)
				if person.cargo_kind == "food" and active.work >= DAY_TICKS:
					world.metrics.spoiled_food += person.cargo
					person.cargo = 0
					person.cargo_kind = ""
					set_task(world, person, {})
			else: set_task(world, person, {})
		"supply":
			if person.cargo == 0:
				var missing := int(COST[value.kind]) - int(value.delivered) - in_transit(world, value.id)
				var amount := mini(LOAD, mini(int(home.wood), missing))
				if amount > 0:
					home.wood -= amount
					person.cargo_kind = "wood"
					person.cargo = amount
				else: set_task(world, person, {})
			else:
				value.delivered += person.cargo
				person.cargo = 0
				person.cargo_kind = ""
				set_task(world, person, {})
		"build":
			if value.delivered < int(COST[value.kind]) or not WorldCivilization.materials_ready(value):
				set_task(world, person, {})
				return
			value.work = mini(int(WORK[value.kind]), int(value.work) + credit)
			if value.work >= int(WORK[value.kind]):
				value.ready = true
				WorldSociety.invalidate(world)
				world.metrics.built_wood += int(COST[value.kind])
				world.log_event("Стройка завершена", "%s: %s готов%s." % [home.name, NAMES[value.kind], "о" if value.kind == "farm" else ""])
				set_task(world, person, {})
		"plant":
			if active.work < 5: return
			if person.cargo_kind == "seed" and person.cargo == 1 and not value.planted:
				person.cargo = 0
				person.cargo_kind = ""
				world.metrics.seed_food += 1
				value.planted = true
				value.growth = 0
			set_task(world, person, {})
		"harvest":
			if active.work < 4: return
			var amount := mini(LOAD, int(value.stock))
			value.stock -= amount
			person.cargo = amount
			person.cargo_kind = "food" if amount > 0 else ""
			set_task(world, person, {})
		"eat":
			var amount := mini(2, int(home.food))
			home.food -= amount
			person.rations += amount
			set_task(world, person, {})
		"rest":
			person.energy = minf(100, person.energy + 2.0)
			person.health = minf(100, person.health + 0.125)
			if person.energy >= 95: set_task(world, person, {})
		"visit":
			if active.work >= 5:
				WorldSocial.finish_visit(world, person, home)
				set_task(world, person, {})
	person.energy = maxf(0, person.energy - 0.125) if active.kind != "rest" else person.energy

static func prepare_seed(world, person: Dictionary, home: Dictionary) -> bool:
	if person.task.is_empty() or person.task.kind != "plant" or person.cargo_kind == "seed": return true
	var center := Vector2i(home.x, home.y)
	if not move(world, person, center, home): return false
	if home.food <= 0:
		set_task(world, person, {})
		return false
	home.food -= 1
	person.cargo = 1
	person.cargo_kind = "seed"
	return false

static func lose_cargo(world, person: Dictionary) -> void:
	if WorldCivilization.GOODS.has(person.cargo_kind): world.industry.lost[person.cargo_kind] += int(person.cargo)
	world.metrics.lost_food += int(person.rations) + (int(person.cargo) if person.cargo_kind in ["food", "seed"] else 0)
	world.metrics.lost_wood += int(person.cargo) if person.cargo_kind == "wood" else 0
	set_task(world, person, {})

static func step(world) -> void:
	WorldSocial.tick(world)
	world.claims.clear()
	for person in world.people: step_claim(world, person)
	for value in world.buildings: step_farm(world, value)
	if world.ticks % DAY_TICKS == 0:
		for home in world.towns: plan(world, home)
	if world.ticks % (DAY_TICKS * 4) == 0:
		for home in world.towns: step_spoil(world, home)
	for i in range(world.people.size() - 1, -1, -1): step_person(world, i)

static func step_claim(world, person: Dictionary) -> void:
	if not person.task.is_empty():
		var key := claim_key(person.task)
		if not key.is_empty(): world.claims[key] = person.id

static func step_farm(world, value: Dictionary) -> void:
	if not value.ready or value.kind != "farm" or not value.planted: return
	if world.ticks < world.drought_until or world.fires.has(Vector2i(value.x, value.y)): return
	var home := town(world, value.town)
	var advanced := WorldSociety.active(world, home, "rotation")
	value.growth += 1
	if value.growth >= (50 if advanced else 60):
		value.stock = clampi(roundi((24 if advanced else 18) * WorldClimate.yield_factor(world, Vector2i(value.x, value.y))), 1, 36)
		if advanced: WorldSociety.use(world, home, "rotation")
		value.planted = false
		value.growth = 0
		world.metrics.crop_food += value.stock

static func step_spoil(world, home: Dictionary) -> void:
	var rate := 0.01 if count(world, home, "store") > 0 else 0.04
	if home.food > 0 and WorldSociety.active(world, home, "preservation"):
		rate = 0.005
		WorldSociety.use(world, home, "preservation")
	var amount := floori(home.food * rate)
	home.food -= amount
	world.metrics.spoiled_food += amount

static func step_person(world, i: int) -> void:
	var person: Dictionary = world.people[i]
	person.age += 1
	person.hunger += WorldLife.hunger_rate(world, person)
	if world.journey_people.has(person.id):
		WorldTravel.member_step(world, person)
		return
	if WorldMaritime.onboard(world, person.id):
		WorldMaritime.crew_step(world, person)
		return
	var current := Vector2i(person.x, person.y)
	if world.fires.has(current):
		person.hunger += 6
		person.health = maxf(0, person.health - 8)
		WorldSociety.invalidate(world)
		set_task(world, person, {})
		for direction in WorldState.DIRECTIONS:
			var safe: Vector2i = current + direction
			if world.walkable(safe) and not world.fires.has(safe):
				person.x = safe.x
				person.y = safe.y
				world.track_person_move(person, current)
				break
	if person.hunger >= NUTRITION:
		if person.rations > 0:
			person.rations -= 1
			person.hunger -= NUTRITION
			world.metrics.eaten_food += 1
		elif person.cargo_kind == "food" and person.cargo > 0:
			person.cargo -= 1
			person.hunger -= NUTRITION
			world.metrics.eaten_food += 1
			if person.cargo == 0:
				person.cargo_kind = ""
				set_task(world, person, {})
		elif WorldLife.adult(world, person) and person.hunger >= 40 and world.food_at(current) > 0:
			world._set_food(current, world.food_at(current) - 1)
			person.hunger -= NUTRITION
			world.metrics.harvested_food += 1
			world.metrics.eaten_food += 1
	if person.hunger > 100 or person.health <= 0:
		world.remove_person(i, "голод" if person.hunger > 100 else "огонь или отсутствие ухода")
		return
	var home := town(world, person.home)
	if home.is_empty() or not navigation(world, home).parents.has(Vector2i(person.x, person.y)):
		home = {}
		for candidate in world.towns:
			if current.distance_squared_to(Vector2i(candidate.x, candidate.y)) <= RANGE * RANGE and navigation(world, candidate).parents.has(current):
				home = candidate
				break
		var new_home: int = int(home.id) if not home.is_empty() else -1
		if person.home != new_home:
			world.life_dirty = true
			WorldSociety.invalidate(world)
			world.population_dirty = true
			world.workforce.plans.clear(); world.workforce.contributions.clear()
		person.home = new_home
		set_task(world, person, {})
	if not WorldLife.adult(world, person):
		WorldLife.dependent_step(world, person, home)
		if person.health <= 0: world.remove_person(i, "отсутствие ухода")
		return
	person.guardian = -1
	if person.job in ["child", "teen"]: person.job = "settler"
	if home.is_empty():

		var best := -INF
		var next := Vector2i(person.x, person.y)
		for direction in WorldState.DIRECTIONS:
			var cell: Vector2i = next + direction
			if not world.walkable(cell) or world.fires.has(cell): continue
			var score: float = world.food_at(cell) + world.rng.randf()
			if score > best:
				best = score
				current = cell
		var previous := Vector2i(person.x, person.y)
		person.x = current.x
		person.y = current.y
		world.track_person_move(person, previous)
		return
	if not person.lesson.is_empty() and WorldSocial.student_step(world, person, home): return
	if not prepare_seed(world, person, home): return
	if person.cargo == 0 and person.task.get("kind", "") != "care" and not WorldLife.care_candidate(world, person).is_empty(): WorldLife.assign_care(world, person, home)
	execute(world, person, home)


static func describe(person: Dictionary) -> String:
	if person.task.is_empty(): return "Выбирает следующую задачу"
	var text: String = TASKS.get(person.task.kind, "Работает")
	if person.cargo > 0: text += " · %d %s" % [person.cargo, "еды" if person.cargo_kind in ["food", "seed"] else ("древесины" if person.cargo_kind == "wood" else WorldCivilization.GOODS.get(person.cargo_kind,"материалов"))]
	return text

static func status(world, home: Dictionary) -> String:
	if food_days(world, home) < 2: return "Приоритет — еда"
	for value in world.buildings:
		if value.town == home.id and not value.ready:
			return "%s: материалы %d/%d · работа %d/%d" % [NAMES[value.kind], value.delivered, COST[value.kind], value.work, WORK[value.kind]]
	var forest_left := false
	for cell in navigation(world, home).wood:
		if world.wood_at(cell) > 0:
			forest_left = true
			break
	if not forest_left: return "Поблизости нет леса"
	return "Запасы и хозяйство развиваются"

static func restore(world, data: Dictionary) -> bool:
	if not data.get("buildings") is Array or data.buildings.size() > WorldState.MAX_BUILDINGS or not data.get("metrics") is Dictionary: return false
	for key in METRICS:
		if data.version < 4 and key in ["births", "deaths"]: continue
		if data.version < 5 and key in ["helped_food", "lessons"]: continue
		if data.version < 6 and key in ["research_work", "discoveries"]: continue
		if data.version < 7 and key in ["processed_food", "processed_wood"]: continue
		if not WorldState._integer(data.metrics.get(key)) or data.metrics[key] < 0: return false
		world.metrics[key] = int(data.metrics[key])
	var ids := {}
	for person in world.people: ids[person.id] = true
	for home in world.towns: ids[home.id] = true
	for source in data.buildings:
		if not source is Dictionary or not source.get("kind") is String or not COST.has(source.kind): return false
		for key in ["id", "town", "x", "y", "delivered", "work", "growth", "stock", "integrity"]:
			if not WorldState._integer(source.get(key)): return false
		if not source.get("ready") is bool or not source.get("planted") is bool: return false
		if source.id <= 0 or ids.has(int(source.id)) or source.id >= world.next_id or town(world, source.town).is_empty(): return false
		if source.delivered < 0 or source.delivered > int(COST[source.kind]) or source.work < 0 or source.work > int(WORK[source.kind]): return false
		if source.ready and (source.delivered != int(COST[source.kind]) or source.work != int(WORK[source.kind])): return false
		if source.integrity <= 0 or source.integrity > 12 or source.stock < 0 or source.stock > 36 or source.growth < 0 or source.growth >= 60: return false
		if source.kind != "farm" and (source.stock != 0 or source.growth != 0 or source.planted): return false
		if (source.planted and source.stock > 0) or (not source.ready and (source.planted or source.stock > 0 or source.growth > 0)): return false
		var value: Dictionary = source.duplicate()
		for key in ["id", "town", "x", "y", "delivered", "work", "growth", "stock", "integrity"]: value[key] = int(value[key])
		var rect := footprint(value)
		for y in rect.size.y:
			for x in rect.size.x:
				var cell := rect.position + Vector2i(x, y)
				if not world.walkable(cell) or world.occupied.has(cell): return false
				world.occupied[cell] = value
		ids[value.id] = true
		world.buildings.append(value)
		world.building_index[value.id] = value
	var used_claims := {}
	for person in world.people:
		if not person.get("name") is String or not JOBS.has(person.get("job")): return false
		for key in ["rations", "cargo"]:
			if not WorldState._integer(person.get(key)): return false
			person[key] = int(person[key])
		if person.rations < 0 or person.rations > 2 or person.cargo < 0 or person.cargo > LOAD: return false
		if person.get("cargo_kind") not in ["", "food", "wood", "seed"] and not WorldCivilization.GOODS.has(person.get("cargo_kind")): return false
		if (person.cargo == 0) != (person.cargo_kind == "") or (person.cargo_kind == "seed" and person.cargo != 1): return false
		if not (person.get("energy") is float or person.get("energy") is int) or not is_finite(float(person.energy)) or person.energy < 0 or person.energy > 100: return false
		person.energy = float(person.energy)
		if person.home != -1 and town(world, person.home).is_empty(): return false
		if not person.get("task") is Dictionary: return false
		if person.task.is_empty(): continue
		if not TASKS.has(person.task.get("kind")): return false
		for key in ["x", "y", "building", "work"]:
			if not WorldState._integer(person.task.get(key)): return false
			person.task[key] = int(person.task[key])
		if person.task.work < 0 or (not world.walkable(Vector2i(person.task.x, person.task.y)) and not WorldMaritime.saved_onboard(data, person.id)): return false
		if person.task.kind == "fish":
			if not WorldState._integer(person.task.get("water_x")) or not WorldState._integer(person.task.get("water_y")): return false
			var water := Vector2i(person.task.water_x, person.task.water_y)
			if water.distance_to(Vector2i(person.task.x, person.task.y)) != 1 or world.terrain_at(water) != WorldState.Terrain.WATER: return false
		if person.task.kind in ["build", "plant", "harvest", "supply"]:
			var value := building(world, person.task.building)
			if value.is_empty() or value.town != person.home: return false
			if person.task.kind in ["plant", "harvest"] and (value.kind != "farm" or not value.ready): return false
		var claim := claim_key(person.task)
		if not claim.is_empty():
			if used_claims.has(claim): return false
			used_claims[claim] = true
	for value in world.buildings:
		if not value.ready and value.delivered + in_transit(world, value.id) > int(COST[value.kind]): return false
	return true
