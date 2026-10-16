class_name WorldExploration
extends RefCounted

const MAX_RANGE := 48
const RANGE_STEP := 8
const SURVEY_WORK := 4
const RETRY_DAYS := 4

static func radius(home: Dictionary) -> int:
	return int(home.get("survey", {}).get("radius", WorldEconomy.RANGE))

static func register(world, home: Dictionary) -> void:
	var center := WorldState.chunk_of(Vector2i(home.x, home.y))
	for y in range(-2, 3):
		for x in range(-2, 3):
			var key := center + Vector2i(x, y)
			if not world.survey_regions.has(key): world.survey_regions[key] = []
			if not world.survey_regions[key].has(home.id): world.survey_regions[key].append(int(home.id))

static func invalidate(world, cell: Vector2i) -> void:
	for id in world.survey_regions.get(WorldState.chunk_of(cell), []):
		var home: Dictionary = WorldEconomy.town(world, id)
		if not home.is_empty() and home.has("survey"): home.survey.dirty = true

static func forget(world, home: Dictionary) -> void:
	var center := WorldState.chunk_of(Vector2i(home.x, home.y))
	for y in range(-2, 3):
		for x in range(-2, 3):
			var key := center + Vector2i(x, y)
			if not world.survey_regions.has(key): continue
			world.survey_regions[key].erase(int(home.id))
			if world.survey_regions[key].is_empty(): world.survey_regions.erase(key)

static func prepare(world, home: Dictionary) -> void:
	if not home.has("survey"): return
	var state: Dictionary = home.survey
	if state.pending_radius > state.radius:
		state.radius = state.pending_radius
		if world.navigation.has(home.id):
			var retired := {home.id:world.navigation[home.id]}
			world.navigation.erase(home.id)
			world.navigation_cleanup.append(WorldNavigationCleanupJob.new(retired))
	if state.dirty:
		state.dirty = false
		state.exhausted = false
		state.next_tick = mini(int(state.next_tick), world.ticks)

static func state_for(world, home: Dictionary) -> Dictionary:
	if not home.has("survey"):
		home.survey = {"radius": WorldEconomy.RANGE, "pending_radius": WorldEconomy.RANGE, "next_tick": world.ticks, "exhausted": false, "reason": "", "report": false, "trips": 0, "dirty": false}
		register(world, home)
	return home.survey

static func assign(world, member: Dictionary, home: Dictionary) -> bool:
	if member.hunger >= 35 or member.energy < 50 or member.birth_due >= 0 or member.cargo > 0: return false
	if world.claims.has("explore:%d" % home.id): return false
	var reason := ""
	if WorldEconomy.food_days(world, home) < 6 and not world.workforce.has_resource(world, home, "food"):
		reason = "food"
	elif home.wood < 24 and not world.workforce.has_resource(world, home, "wood"):
		reason = "wood"
	if reason.is_empty() and WorldEconomy.members(world,home).size()>=8 and WorldEconomy.food_days(world,home)>=8 and home.wood>=8:
		reason = "territory"
	if reason.is_empty(): return false
	if reason == "wood" and WorldEconomy.food_days(world, home) < 2: return false
	var state := state_for(world, home)
	if state.exhausted or state.radius >= MAX_RANGE or world.ticks < state.next_tick: return false
	if member.rations < 2:
		if Vector2i(member.x, member.y) != Vector2i(home.x, home.y) or home.food < 2 - member.rations: return false
	var navigation: Dictionary = WorldEconomy.navigation(world, home)
	var candidates: Array[Vector2i] = navigation.cells
	var center := Vector2i(home.x, home.y)
	var current := Vector2i(member.x, member.y)
	var allowance := floori((2 * WorldEconomy.NUTRITION + 35 - member.hunger) / maxf(0.625, WorldLife.hunger_rate(world, member))) - SURVEY_WORK
	var target := WorldState.NO_CELL
	var best := -INF
	var frontier_exists := false
	for cell in candidates:
		if absi(cell.x - center.x) + absi(cell.y - center.y) < int(state.radius): continue
		if world.fires.has(cell) or world.occupied.has(cell): continue
		frontier_exists = true
		if 2 * int(navigation.distances[cell]) + int(navigation.distances.get(current, 0)) > allowance: continue
		var score := float(cell.distance_squared_to(center))
		if cell.x >= center.x: score += float(member.traits.curiosity) * 0.1
		if score > best:
			best = score
			target = cell
	if target == WorldState.NO_CELL:
		state.exhausted = not frontier_exists
		state.next_tick = world.ticks + WorldEconomy.DAY_TICKS
		state.reason = reason
		return false
	var provision: int = 2 - int(member.rations)
	home.food -= provision
	member.rations += provision
	var task := WorldEconomy.task("explore", target, home.id)
	task.phase = "outbound"
	task.reason = reason
	task.radius = int(state.radius)
	task.surveyed = false
	state.reason = reason
	WorldEconomy.set_task(world, member, task)
	member.job = "scout"
	world.log_event("Разведка окрестностей", "%s: %s ищет %s за пределами привычных мест." % [home.name, member.name, {"food":"еду","wood":"лес","territory":"земли для новых поселений"}[reason]])
	return true

static func assign_ruins(world, member: Dictionary, home: Dictionary) -> bool:
	if world.heritage.sites.is_empty() or member.hunger >= 25 or member.energy < 60 or member.birth_due >= 0 or member.cargo > 0 or world.claims.has("explore:%d" % home.id): return false
	if WorldEconomy.food_days(world,home) < 6: return false
	var provision := 2-int(member.rations)
	if provision > 0 and (Vector2i(member.x,member.y) != Vector2i(home.x,home.y) or home.food < provision): return false
	var nav: Dictionary = WorldEconomy.navigation(world,home)
	var cell: Vector2i = world.heritage.research_target(world,home,nav)
	if cell == WorldState.NO_CELL or world.fires.has(cell): return false
	var current := Vector2i(member.x,member.y)
	var distance: int = 2*int(nav.distances[cell])+int(nav.distances.get(current,0))
	if distance*WorldLife.hunger_rate(world,member)+SURVEY_WORK > 2*WorldEconomy.NUTRITION+25-member.hunger: return false
	home.food -= provision; member.rations += provision
	var state := state_for(world,home)
	var task := WorldEconomy.task("explore",cell,home.id)
	task.phase = "outbound"; task.reason = "ruins"; task.radius = int(state.radius); task.surveyed = false
	WorldEconomy.set_task(world,member,task); member.job = "scout"
	world.log_event("По следам прежних жителей","%s: %s отправляется обследовать старые основания." % [home.name,member.name])
	return true

static func execute(world, member: Dictionary, home: Dictionary) -> void:
	var task: Dictionary = member.task
	var target := Vector2i(task.x, task.y)
	if task.phase == "outbound" and (member.hunger >= 60 or member.energy < 12 or world.fires.has(target) or not world.walkable(target)):
		task.phase = "returning"
		task.x = home.x
		task.y = home.y
		target = Vector2i(home.x, home.y)
	if not WorldEconomy.navigation(world, home).parents.has(target):
		WorldEconomy.set_task(world, member, {})
		return
	if not WorldEconomy.move(world, member, target, home): return
	if task.phase == "outbound":
		task.work += 1
		if task.work < SURVEY_WORK: return
		task.surveyed = true
		task.phase = "returning"
		task.x = home.x
		task.y = home.y
		return
	var state := state_for(world, home)
	state.next_tick = world.ticks + WorldEconomy.DAY_TICKS * RETRY_DAYS
	if task.surveyed and task.reason == "ruins":
		WorldVocation.milestone(member,"explore")
		WorldEconomy.set_task(world,member,{})
		return
	if task.surveyed:
		WorldVocation.milestone(member, "explore")
		state.pending_radius = mini(MAX_RANGE, int(task.radius) + RANGE_STEP)
		state.report = true
		state.trips = mini(1000000, int(state.trips) + 1)
	WorldEconomy.set_task(world, member, {})

static func report(world, home: Dictionary) -> void:
	if not home.has("survey") or not home.survey.report: return
	var state: Dictionary = home.survey
	state.report = false
	var found := false
	var nav: Dictionary = world.navigation[home.id]
	if state.reason=="territory":
		world.log_event("Новые земли обследованы","%s: разведчики изучили окрестности в радиусе %d клеток." % [home.name,state.radius])
		return
	for cell in nav[state.reason]:
		if world.fires.has(cell) or world.occupied.has(cell): continue
		if (world.food_at(cell) if state.reason == "food" else world.wood_at(cell)) > 0:
			found = true
			break
	world.log_event("Разведчики вернулись", "%s: %s." % [home.name, ("найдены новые источники еды" if state.reason == "food" else "найден доступный лес") if found else "дальние окрестности обследованы, нужный ресурс пока не найден"])

static func describe(world, home: Dictionary) -> String:
	if world.claims.has("explore:%d" % home.id):
		return "Разведчик ищет " + {"food":"еду","wood":"лес","territory":"новые земли","ruins":"старые поселения"}.get(home.get("survey",{}).get("reason","wood"),"новые земли")
	if not home.has("survey"): return ""
	var state: Dictionary = home.survey
	if state.reason == "wood" and not world.workforce.has_resource(world, home, "wood"):
		return "Лес не найден в доступных окрестностях" if state.exhausted or state.radius >= MAX_RANGE else "Не хватает древесины · готовится разведка"
	if state.reason == "food" and not world.workforce.has_resource(world, home, "food"):
		return "Наземная еда не найдена · нужен другой источник" if state.exhausted or state.radius >= MAX_RANGE else "Ищут новые источники еды"
	return ""

static func restore(world) -> bool:
	for home in world.towns:
		if not home.has("survey"): continue
		if not home.survey is Dictionary: return false
		var state: Dictionary = home.survey
		for key in ["radius", "pending_radius", "next_tick", "trips"]:
			if not WorldState._integer(state.get(key)): return false
			state[key] = int(state[key])
		if state.radius < WorldEconomy.RANGE or state.radius > MAX_RANGE or (state.radius - WorldEconomy.RANGE) % RANGE_STEP != 0: return false
		if state.pending_radius < state.radius or state.pending_radius > mini(MAX_RANGE, state.radius + RANGE_STEP): return false
		if (state.pending_radius - WorldEconomy.RANGE) % RANGE_STEP != 0: return false
		if state.next_tick < 0 or state.next_tick > world.ticks + WorldEconomy.DAY_TICKS * RETRY_DAYS: return false
		if state.trips < 0 or state.trips > 1000000 or not state.get("exhausted") is bool or not state.get("report") is bool or not state.get("dirty") is bool: return false
		if state.get("reason") not in ["", "food", "wood", "territory"] or (state.report and state.reason.is_empty()): return false
		register(world, home)
	return true
