class_name WorldLandworks
extends RefCounted

const SPEC: Dictionary = preload("res://data/landworks.json").data
const SEARCH_LIMIT := 128
const COOLDOWN := WorldEconomy.DAY_TICKS*3

static func state_for(world, home: Dictionary) -> Dictionary:
	if not home.has("landworks"):
		home.landworks = {"next_tick":world.ticks,"cursor":0,"serial":0,"completed":{"forest":0,"cultivate":0,"pass":0,"reclaim":0},"project":{}}
	return home.landworks

static func expanding(world, home: Dictionary) -> bool:
	return WorldEconomy.members(world,home).size()>=12 and WorldExploration.radius(home)>=32 and WorldEconomy.food_days(world,home)>=10 and home.wood>=12

static func available(world, home: Dictionary, mode: String) -> bool:
	for method in SPEC[mode].methods:
		if not WorldSociety.mastered(world,home,method): return false
	return true

static func clear_site(world, cell: Vector2i) -> bool:
	if not world.inside(cell) or world.fires.has(cell) or world.occupied.has(cell) or world.networks.bridges.has(cell) or world.networks.roads.has(cell): return false
	if world.heritage.at(cell).is_empty(): return true
	return false

static func suitable(world, home: Dictionary, mode: String, cell: Vector2i, stand: Vector2i, nav: Dictionary) -> bool:
	if not clear_site(world,cell) or world.terrain_at(cell)!=int(SPEC[mode].from): return false
	if not nav.parents.has(stand) or not world.walkable(stand) or world.fires.has(stand): return false
	if absi(cell.x-stand.x)+absi(cell.y-stand.y) > 1: return false
	var origin := Vector2i(home.x,home.y)
	var distance := absi(cell.x-origin.x)+absi(cell.y-origin.y)
	if distance<5 or distance>mini(20,int(nav.reach)): return false
	if mode in ["forest","cultivate"] and cell!=stand: return false
	if mode in ["pass","reclaim"] and cell==stand: return false
	for direction in WorldState.DIRECTIONS:
		if world.occupied.has(cell+direction): return false
	if mode=="forest":
		if WorldClimate.biome(world,cell)>=4 or (WorldClimate.biome(world,cell)==1 and WorldEconomy.count(world,home,"irrigation")==0): return false
		if world.landscape.paths.has(cell) and WorldLandscape.stage(world.landscape.wear_at(world.landscape.paths[cell],world.ticks))>0: return false
		var forest := 0
		for direction in WorldState.DIRECTIONS:
			if world.terrain_at(cell+direction)==WorldState.Terrain.FOREST: forest += 1
		return forest<3
	if mode=="cultivate":
		var fertile := false
		var wet := WorldSociety.mastered(world,home,"waterworks") and WorldEconomy.count(world,home,"irrigation")>0
		for direction in WorldState.DIRECTIONS:
			var ground: int = world.terrain_at(cell+direction)
			fertile = fertile or ground in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST]
			wet = wet or ground==WorldState.Terrain.WATER
		return fertile and wet
	if mode=="pass":
		for direction in WorldState.DIRECTIONS:
			var other: Vector2i = cell+direction
			if other!=stand and world.walkable(other) and not nav.parents.has(other) and absi(other.x-origin.x)+absi(other.y-origin.y)<=int(nav.reach): return true
		return false
	if not world.voyages.is_empty(): return false
	var land := 0
	for direction in WorldState.DIRECTIONS:
		if world.terrain_at(cell+direction) in [WorldState.Terrain.SAND,WorldState.Terrain.GRASS,WorldState.Terrain.FOREST]: land += 1
	return land>=2

static func assign(world, member: Dictionary, home: Dictionary) -> bool:
	var state: Dictionary = home.get("landworks",{})
	var project: Dictionary = state.get("project",{})
	if project.is_empty() or project.ready or world.claims.has("terraform:%d" % home.id): return false
	var spec: Dictionary = SPEC[project.mode]
	if member.skills[spec.skill]<int(spec.expert) or member.energy<50 or member.hunger>=25 or member.birth_due>=0 or member.cargo>0: return false
	if WorldEconomy.food_days(world,home)<6 or not available(world,home,project.mode): return false
	if not WorldCivilization.inputs_available(world,home,{spec.material:int(spec.cost)}): return false
	var task := WorldEconomy.task("terraform",Vector2i(home.x,home.y),home.id)
	task.phase = "fetch"; task.serial = int(state.serial)
	WorldEconomy.set_task(world,member,task)
	member.job = "farmer" if project.mode=="cultivate" else ("logger" if project.mode=="forest" else "builder")
	return true

static func execute(world, member: Dictionary, home: Dictionary) -> void:
	var state: Dictionary = home.get("landworks",{})
	var project: Dictionary = state.get("project",{})
	var task: Dictionary = member.task
	if project.is_empty() or project.ready or task.serial!=state.serial or not available(world,home,project.mode):
		WorldEconomy.set_task(world,member,{}); return
	var spec: Dictionary = SPEC[project.mode]
	var cell := Vector2i(project.x,project.y)
	var stand := Vector2i(project.stand_x,project.stand_y)
	var nav: Dictionary = WorldEconomy.navigation(world,home)
	if not suitable(world,home,project.mode,cell,stand,nav):
		state.project = {}; state.next_tick = world.ticks+WorldEconomy.DAY_TICKS
		WorldEconomy.set_task(world,member,{}); return
	if task.phase=="fetch":
		if not WorldEconomy.move(world,member,Vector2i(home.x,home.y),home): return
		if not WorldCivilization.inputs_available(world,home,{spec.material:int(spec.cost)}) or member.cargo>0:
			WorldEconomy.set_task(world,member,{}); return
		world.networks.take(world,home,spec.material,int(spec.cost))
		member.cargo = int(spec.cost); member.cargo_kind = spec.material
		task.phase = "work"; task.x = stand.x; task.y = stand.y
		return
	if member.cargo_kind!=spec.material or member.cargo!=int(spec.cost):
		WorldEconomy.set_task(world,member,{}); return
	if not WorldEconomy.move(world,member,stand,home): return
	if WorldLife.years(world,member)>=60 and (world.ticks+int(member.id))%2: return
	project.work = mini(int(spec.work),int(project.work)+WorldSocial.work_credit(world,member,spec.skill))
	WorldSocial.practice(world,member,spec.skill)
	member.energy = maxf(0,member.energy-0.25)
	if project.work<int(spec.work): return
	if spec.material in ["food","wood"]: world.metrics["processed_"+spec.material] += int(spec.cost)
	else: world.industry.consumed[spec.material] += int(spec.cost)
	member.cargo = 0; member.cargo_kind = ""; project.ready = true
	for method in spec.methods: WorldSociety.use(world,home,method,member)
	WorldEconomy.set_task(world,member,{})

static func apply(world, home: Dictionary) -> void:
	var state: Dictionary = home.landworks
	var project: Dictionary = state.project
	if project.mode=="reclaim" and not world.voyages.is_empty(): return
	var cell := Vector2i(project.x,project.y)
	var nav: Dictionary = world.navigation.get(home.id,{})
	if not nav.is_empty() and suitable(world,home,project.mode,cell,Vector2i(project.stand_x,project.stand_y),nav):
		var ids: Array = world.navigation.keys()
		world._set_terrain(cell,int(SPEC[project.mode].to))
		for id in ids:
			if not world.navigation.has(id) and world.stepping and not world.networks.navigation_queue.has(int(id)): world.networks.navigation_queue.append(int(id))
		world.site_cache.clear()
		if project.mode=="forest":
			world.stumps.erase(cell); world.landscape.remove_site(cell,"stump")
		if project.mode=="pass":
			world.mineral_deposits.erase(cell); world.landscape.remove_site(cell,"quarry")
		state.completed[project.mode] = mini(1000000,int(state.completed[project.mode])+1)
		world.log_event("Земли меняются","%s: %s · участок (%d, %d)." % [home.name,SPEC[project.mode].name.to_lower(),cell.x,cell.y])
		world.terrain_changed.emit()
	state.project = {}; state.next_tick = world.ticks+COOLDOWN

static func restore(world) -> bool:
	for home in world.towns:
		if not home.has("landworks"): continue
		if not home.landworks is Dictionary: return false
		var state: Dictionary = home.landworks
		for key in ["next_tick","cursor","serial"]:
			if not WorldState._integer(state.get(key)) or state[key]<0: return false
			state[key] = int(state[key])
		if state.next_tick>world.ticks+COOLDOWN or state.cursor>1000000 or state.serial>1000000000: return false
		if not state.get("completed") is Dictionary or not state.get("project") is Dictionary: return false
		for mode in SPEC:
			if not WorldState._integer(state.completed.get(mode)) or state.completed[mode]<0 or state.completed[mode]>1000000: return false
			state.completed[mode] = int(state.completed[mode])
		var project: Dictionary = state.project
		if project.is_empty(): continue
		if not project.get("mode") is String or not SPEC.has(project.mode) or not project.get("ready") is bool: return false
		for key in ["x","y","stand_x","stand_y","work"]:
			if not WorldState._integer(project.get(key)): return false
			project[key] = int(project[key])
		var cell := Vector2i(project.x,project.y)
		var stand := Vector2i(project.stand_x,project.stand_y)
		if not world.inside(cell) or not world.inside(stand) or absi(cell.x-home.x)+absi(cell.y-home.y)>20 or absi(cell.x-stand.x)+absi(cell.y-stand.y)>1: return false
		if project.work<0 or project.work>int(SPEC[project.mode].work) or project.ready!=(project.work==int(SPEC[project.mode].work)): return false
	return true
