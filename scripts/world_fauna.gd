class_name WorldFauna
extends RefCounted

static var SPEC: Dictionary = load_catalog()
const LIMIT := 256
const GROUP_LIMIT := 16
var herds: Array[Dictionary] = []
var index: Dictionary = {}
var regions: Dictionary = {}
var visited: Dictionary = {}
var next_id := 1
var revision := 0
var random := RandomNumberGenerator.new()
var offers: Dictionary = {}
var owner_counts: Dictionary = {}
var terrain_revision := -1

static func load_catalog() -> Dictionary:
	var source: Dictionary = preload("res://data/fauna.json").data.duplicate(true)
	for species in source:
		for key in ["meat","sprite"]: source[species][key] = int(source[species][key])
		var biomes: Array[int] = []
		for biome in source[species].biomes: biomes.append(int(biome))
		source[species].biomes = biomes
	return source

func initialize(seed_value: int) -> void:
	random.seed = hash("%d:fauna" % seed_value)

func add(world, species: String, cell: Vector2i, count: int, owner: int = -1) -> Dictionary:
	if herds.size()>=LIMIT or count<1 or count>GROUP_LIMIT or not SPEC.has(species) or not safe(world,cell): return {}
	var value := {"id":next_id,"species":species,"x":cell.x,"y":cell.y,"count":count,"home":owner,"hunger":0,"milk_tick":world.ticks,"wool_tick":world.ticks,"birth_tick":world.ticks+WorldEconomy.DAY_TICKS*6}
	next_id += 1; owner_counts[owner] = int(owner_counts.get(owner,0))+count; herds.append(value); index[value.id] = value; _index(value); revision += 1; offers.clear()
	return value

func _index(herd: Dictionary) -> void:
	var key := WorldState.chunk_of(Vector2i(herd.x,herd.y))
	if not regions.has(key): regions[key] = []
	regions[key].append(int(herd.id))

func remove(herd: Dictionary) -> void:
	var key := WorldState.chunk_of(Vector2i(herd.x,herd.y))
	regions[key].erase(int(herd.id))
	if regions[key].is_empty(): regions.erase(key)
	owner_counts[herd.home] = int(owner_counts.get(herd.home,0))-int(herd.count)
	herds.erase(herd); index.erase(int(herd.id)); offers.clear(); revision += 1

func move(herd: Dictionary, cell: Vector2i) -> void:
	var key := WorldState.chunk_of(Vector2i(herd.x,herd.y))
	regions[key].erase(int(herd.id))
	if regions[key].is_empty(): regions.erase(key)
	herd.x = cell.x; herd.y = cell.y
	_index(herd); offers.clear(); revision += 1

static func safe(world, cell: Vector2i) -> bool:
	if not world.inside(cell) or world.fires.has(cell) or world.terrain_at(cell) not in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST]: return false
	var building: Dictionary = world.occupied.get(cell,{})
	return building.is_empty() or (building.kind=="pasture" and building.ready)

func at(cell: Vector2i) -> Dictionary:
	for dy in range(-1,2):
		for dx in range(-1,2):
			for id in regions.get(WorldState.chunk_of(cell)+Vector2i(dx,dy),[]):
				var herd: Dictionary = index[id]
				if cell.distance_squared_to(Vector2i(herd.x,herd.y))<=1: return herd
	return {}

func nearby(world, home: Dictionary) -> Array:
	var cached: Dictionary = offers.get(home.id,{})
	if cached.get("revision",-1)==revision and cached.get("tick",-1)==world.ticks: return cached.ids
	var ids: Array[int] = []
	var nav: Dictionary = world.navigation.get(home.id,{})
	if nav.is_empty(): return ids
	var origin := Vector2i(home.x,home.y)
	var first := WorldState.chunk_of(origin-Vector2i.ONE*int(nav.reach))
	var last := WorldState.chunk_of(origin+Vector2i.ONE*int(nav.reach))
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			for id in regions.get(Vector2i(x,y),[]):
				var herd: Dictionary = index[id]
				if nav.parents.has(Vector2i(herd.x,herd.y)): ids.append(int(id))
	offers[home.id] = {"revision":revision,"tick":world.ticks,"ids":ids}
	return ids

func owned(home: Dictionary) -> int:
	return int(owner_counts.get(home.id,0))

func resize(herd: Dictionary, count: int) -> void:
	if count<=0: remove(herd); return
	owner_counts[herd.home] = int(owner_counts.get(herd.home,0))+count-int(herd.count)
	herd.count = count; offers.clear(); revision += 1

func set_owner(herd: Dictionary, owner: int) -> void:
	owner_counts[herd.home] = int(owner_counts.get(herd.home,0))-int(herd.count)
	herd.home = owner; owner_counts[owner] = int(owner_counts.get(owner,0))+int(herd.count)
	offers.clear(); revision += 1

func assign(world, member: Dictionary, home: Dictionary, food_only: bool = false) -> bool:
	if member.energy<35 or member.hunger>=40 or member.birth_due>=0 or member.cargo>0 or not WorldLife.adult(world,member): return false
	var checked := 0
	for id in nearby(world,home):
		if checked>=12: break
		checked += 1
		var herd: Dictionary = index[id]
		if world.claims.has("herd:%d" % id) or world.fires.has(Vector2i(herd.x,herd.y)): continue
		var action := ""
		if herd.home==home.id:
			if herd.hunger==0 and world.ticks>=herd.milk_tick and home.food<WorldEconomy.food_capacity(world,home)-2: action = "milk"
			elif not food_only and herd.species=="sheep" and world.ticks>=herd.wool_tick and WorldSociety.mastered(world,home,"husbandry") and WorldCivilization.ensure(world,home).stock.wool<24: action = "shear"
		elif herd.home==-1:
			if food_only and WorldEconomy.food_days(world,home)<4 and member.skills.food>=10: action = "hunt"
			elif not food_only and SPEC[herd.species].domestic and member.skills.food>=20 and WorldEconomy.food_days(world,home)>=6 and owned(home)<8 and home.food>=4: action = "tame"
		if action.is_empty(): continue
		var target := Vector2i(home.x,home.y) if action=="tame" else Vector2i(herd.x,herd.y)
		var task := WorldEconomy.task("herd",target)
		task.herd = int(id); task.action = action; task.phase = "fetch" if action=="tame" else "work"
		WorldEconomy.set_task(world,member,task)
		member.job = "herder" if action!="hunt" else "hunter"
		return true
	return false

func execute(world, member: Dictionary, home: Dictionary) -> void:
	var task: Dictionary = member.task
	var herd: Dictionary = index.get(int(task.herd),{})
	if herd.is_empty() or (task.action=="tame" and herd.home!=-1) or (task.action in ["milk","shear"] and herd.home!=home.id) or (task.action=="hunt" and herd.home!=-1):
		WorldEconomy.set_task(world,member,{}); return
	if task.phase=="fetch":
		if not WorldEconomy.move(world,member,Vector2i(home.x,home.y),home): return
		if home.food<2 or member.cargo>0: WorldEconomy.set_task(world,member,{}); return
		home.food -= 2; member.cargo = 2; member.cargo_kind = "food"; task.phase = "work"
	var target := Vector2i(herd.x,herd.y)
	var nav: Dictionary = WorldEconomy.navigation(world,home)
	if not nav.parents.has(target) or not safe(world,target) or (task.action=="tame" and (member.cargo!=2 or member.cargo_kind!="food")):
		WorldEconomy.set_task(world,member,{}); return
	task.x = target.x; task.y = target.y
	if not WorldEconomy.move(world,member,target,home): return
	if task.action=="milk" and (world.ticks<herd.milk_tick or herd.hunger>0): WorldEconomy.set_task(world,member,{}); return
	if task.action=="shear" and (world.ticks<herd.wool_tick or not WorldSociety.mastered(world,home,"husbandry")): WorldEconomy.set_task(world,member,{}); return
	var skill := "food" if task.action=="hunt" else "farm"
	task.work += WorldSocial.work_credit(world,member,skill)
	WorldSocial.practice(world,member,skill)
	member.energy = maxf(0,member.energy-0.25)
	if task.work<(10 if task.action=="tame" else 6): return
	match task.action:
		"tame":
			set_owner(herd,int(home.id)); herd.milk_tick = world.ticks+WorldEconomy.DAY_TICKS
			member.cargo = 0; member.cargo_kind = ""; world.metrics.processed_food += 2
			world.log_event("Приручено стадо","%s: %s · %d животных." % [home.name,SPEC[herd.species].name.to_lower(),herd.count])
		"hunt":
			member.cargo = int(SPEC[herd.species].meat); member.cargo_kind = "food"
			resize(herd,int(herd.count)-1)
			world.metrics.harvested_food += int(member.cargo)
		"milk":
			member.cargo = mini(3,maxi(1,int(herd.count)/3)) if WorldSociety.mastered(world,home,"husbandry") else 1
			member.cargo_kind = "food"; world.metrics.harvested_food += int(member.cargo)
			herd.milk_tick = world.ticks+WorldEconomy.DAY_TICKS
		"shear":
			member.cargo = mini(3,maxi(1,int(herd.count)/3)); member.cargo_kind = "wool"
			world.industry.produced.wool += int(member.cargo); herd.wool_tick = world.ticks+WorldEconomy.DAY_TICKS*3
	if task.action!="hunt" and WorldSociety.mastered(world,home,"husbandry"): WorldSociety.use(world,home,"husbandry",member)
	offers.clear(); revision += 1
	WorldEconomy.set_task(world,member,{})

func repair(world, herd: Dictionary) -> void:
	if herd.home!=-1 and WorldEconomy.town(world,herd.home).is_empty(): set_owner(herd,-1)
	var cell := Vector2i(herd.x,herd.y)
	if not world.chunks.has(WorldState.chunk_of(cell)) or safe(world,cell): return
	for direction in WorldState.DIRECTIONS:
		var next: Vector2i = cell+direction
		if safe(world,next): move(herd,next); return
	remove(herd)

func save() -> Dictionary:
	var known: Array = []
	for key in visited: known.append([key.x,key.y])
	return {"herds":herds.duplicate(true),"visited":known,"next_id":next_id,"rng":str(random.state)}

func restore(world, data: Variant) -> bool:
	initialize(world.world_seed)
	for home in world.towns:
		if home.has("herd_cursor"):
			if not WorldState._integer(home.herd_cursor) or home.herd_cursor<0 or home.herd_cursor>1000000: return false
			home.herd_cursor = int(home.herd_cursor)
	if data==null: return true
	if not data is Dictionary or not data.get("herds") is Array or data.herds.size()>LIMIT or not data.get("visited") is Array or data.visited.size()>WorldState.MAX_CHUNKS: return false
	if not WorldState._integer(data.get("next_id")) or data.next_id<1 or data.next_id>1000000000 or not data.get("rng") is String or not data.rng.is_valid_int(): return false
	next_id = int(data.next_id); random.state = data.rng.to_int()
	for row in data.visited:
		if not row is Array or row.size()!=2 or not WorldState._integer(row[0]) or not WorldState._integer(row[1]): return false
		var key := Vector2i(row[0],row[1])
		if visited.has(key) or not world.inside(key*WorldState.CHUNK_SIZE): return false
		visited[key] = true
	for source in data.herds:
		if not source is Dictionary or not SPEC.has(source.get("species")): return false
		var herd: Dictionary = source.duplicate()
		for key in ["id","x","y","count","home","hunger","milk_tick","wool_tick","birth_tick"]:
			if not WorldState._integer(herd.get(key)): return false
			herd[key] = int(herd[key])
		if herd.id<1 or herd.id>=next_id or index.has(herd.id) or not world.inside(Vector2i(herd.x,herd.y)) or herd.count<1 or herd.count>GROUP_LIMIT or herd.hunger<0 or herd.hunger>3: return false
		if herd.home!=-1 and (WorldEconomy.town(world,herd.home).is_empty() or not SPEC[herd.species].domestic): return false
		for key in ["milk_tick","wool_tick","birth_tick"]:
			if herd[key]<0 or herd[key]>world.ticks+WorldEconomy.DAY_TICKS*6: return false
		owner_counts[herd.home] = int(owner_counts.get(herd.home,0))+int(herd.count)
		herds.append(herd); index[herd.id] = herd; _index(herd)
	for member in world.people:
		if member.task.get("kind","")!="herd": continue
		var task: Dictionary = member.task
		if not WorldState._integer(task.get("herd")) or task.get("action") not in ["hunt","tame","milk","shear"] or task.get("phase") not in ["fetch","work"]: return false
		if not index.has(int(task.herd)) or task.work>32 or (task.phase=="fetch" and task.action!="tame"): return false
		if task.action=="tame" and task.phase=="work" and (member.cargo!=2 or member.cargo_kind!="food"): return false
	return true
