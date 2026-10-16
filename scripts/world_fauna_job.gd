class_name WorldFaunaJob
extends RefCounted

var world
var monthly := false
var terrain_check := false
var phase := 0
var cursor := 0
var sample := 0
var groups: Array = []
var active: Dictionary = {}
var anchors: Dictionary = {}
var caps: Dictionary = {}
var domestic := false
var finished := false

func _init(value) -> void:
	world = value; monthly = world.ticks%WorldEconomy.DAY_TICKS==0
	terrain_check = world.fauna.terrain_revision!=world.revision
	if not monthly:
		phase = 1
		finished = not terrain_check and world.fires.is_empty()
	if not finished: groups = world.fauna.herds.duplicate()

func unit() -> void:
	if finished: return
	if phase==0:
		if cursor>=world.towns.size(): phase = 3 if domestic else 1; cursor = 0; return
		var home: Dictionary = world.towns[cursor]; cursor += 1
		anchors[home.id] = Vector2i(home.x,home.y)
		if world.fauna.owned(home)>0: domestic = true
		var center := WorldState.chunk_of(Vector2i(home.x,home.y))
		for y in range(-2,3):
			for x in range(-2,3): active[center+Vector2i(x,y)] = true
		return
	if phase==3:
		if cursor>=world.buildings.size(): phase = 1; cursor = 0; return
		var building: Dictionary = world.buildings[cursor]; cursor += 1
		if building.kind=="pasture" and building.ready:
			anchors[building.town] = Vector2i(building.x+1,building.y+1); caps[building.town] = 12
		return
	if phase==1:
		if cursor>=groups.size():
			world.fauna.terrain_revision = world.revision
			if monthly: phase = 2; cursor = 0
			else: finished = true
			return
		var herd: Dictionary = groups[cursor]; cursor += 1
		var cell := Vector2i(herd.x,herd.y)
		var key := WorldState.chunk_of(cell)
		if herd.home!=-1 and WorldEconomy.town(world,herd.home).is_empty(): world.fauna.set_owner(herd,-1)
		if monthly and not active.has(key): return
		if not monthly and not world.chunks.has(key): return
		if (terrain_check or world.fires.has(cell)) and not WorldFauna.safe(world,cell):
			var escape := WorldState.NO_CELL
			for direction in WorldState.DIRECTIONS:
				var target: Vector2i = cell+direction
				if WorldFauna.safe(world,target): escape = target; break
			if escape!=WorldState.NO_CELL: world.fauna.move(herd,escape); cell = escape
			elif world.ticks%4==0:
				world.fauna.resize(herd,int(herd.count)-1)
				return
		if not monthly or not world.fauna.index.has(herd.id): return
		_graze(herd,cell)
		return
	if cursor>=world.towns.size() or world.fauna.herds.size()>=WorldFauna.LIMIT: finished = true; return
	var home: Dictionary = world.towns[cursor]
	var nav: Dictionary = world.navigation.get(home.id,{})
	if sample>=16 or nav.is_empty(): cursor += 1; sample = 0; return
	var count: int = home.get("herd_cursor",0)
	var cell: Vector2i = nav.cells[posmod(hash(Vector2i(count,int(home.id))),nav.cells.size())]
	home.herd_cursor = (count+1)%1000001; sample += 1
	var key := WorldState.chunk_of(cell)
	if world.fauna.visited.has(key) or world.fauna.visited.size()>=WorldState.MAX_CHUNKS or not WorldFauna.safe(world,cell) or cell.distance_squared_to(Vector2i(home.x,home.y))<36: return
	world.fauna.visited[key] = true
	var biome := WorldClimate.biome(world,cell)
	var choices: Array[String] = []
	for kind in WorldFauna.SPEC:
		if WorldFauna.SPEC[kind].biomes.has(biome): choices.append(kind)
	if choices.is_empty(): return
	var pick := posmod(hash(Vector3i(world.world_seed,key.x,key.y)),choices.size())
	var herd: Dictionary = world.fauna.add(world,choices[pick],cell,3+posmod(hash(Vector3i(key.x,key.y,world.world_seed+19)),4))
	if not herd.is_empty(): world.log_event("Замечено стадо","%s: %s · %d животных." % [home.name,WorldFauna.SPEC[herd.species].name.to_lower(),herd.count])

func _graze(herd: Dictionary, cell: Vector2i) -> void:
	var need := maxi(1,ceili(float(herd.count)/4.0))
	var selected := cell
	var best: int = world.food_at(cell) if WorldFauna.safe(world,cell) else -1
	var offset: int = world.fauna.random.randi_range(0,3)
	for i in 4:
		var next: Vector2i = cell+WorldState.DIRECTIONS[(offset+i)%4]
		if not WorldFauna.safe(world,next): continue
		if herd.home!=-1:
			var anchor: Vector2i = anchors.get(herd.home,cell)
			var distance := absi(next.x-anchor.x)+absi(next.y-anchor.y)
			var previous := absi(cell.x-anchor.x)+absi(cell.y-anchor.y)
			if distance>12 and distance>=previous: continue
		var food: int = world.food_at(next)
		if food>best: best = food; selected = next
	if selected!=cell: world.fauna.move(herd,selected)
	if best>=need:
		world._set_food(selected,best-need); herd.hunger = 0
	else: herd.hunger = mini(3,int(herd.hunger)+1)
	var adapted: bool = WorldFauna.SPEC[herd.species].biomes.has(WorldClimate.biome(world,selected))
	if not adapted: herd.hunger = mini(3,int(herd.hunger)+1)
	if herd.hunger>=3:
		world.fauna.resize(herd,int(herd.count)-1); herd.hunger = 1
		return
	if world.ticks<herd.birth_tick or herd.count<2 or herd.hunger>0: return
	herd.birth_tick = world.ticks+WorldEconomy.DAY_TICKS*6
	var cap: int = caps.get(herd.home,6)
	if herd.count<cap and world.food_at(selected)>=2:
		world._set_food(selected,world.food_at(selected)-2)
		world.fauna.resize(herd,int(herd.count)+1)
