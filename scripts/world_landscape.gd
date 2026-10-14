class_name WorldLandscape
extends RefCounted

const MAX_PATHS := 8192
const MAX_SCARS := 1024
const MAX_WEAR := 16
const MONTH := 20
const GROUNDS := {"camp":1,"house":1,"farm":1,"store":2,"workshop":2,"archive":1,"kiln":2,"loom":1,"forge":2,"market":2,"school":1,"council":2,"dock":1,"port":2}
var paths: Dictionary = {}
var scars: Dictionary = {}
var path_regions: Dictionary = {}
var site_regions: Dictionary = {}
var scar_regions: Dictionary = {}
var grounds: Dictionary = {}
var versions: Dictionary = {}
var revision := 0

static func stage(wear: int) -> int:
	return 3 if wear >= 12 else (2 if wear >= 7 else (1 if wear >= 3 else 0))

static func wear_at(value: Dictionary, tick: int) -> int:
	return maxi(0,int(value.wear)-maxi(0,tick-int(value.tick))/MONTH)

func bump(key: Vector2i) -> void:
	revision += 1
	versions[key] = revision

func invalidate_area(cell: Vector2i, radius: int) -> void:
	var low := WorldState.chunk_of(cell-Vector2i.ONE*radius)
	var high := WorldState.chunk_of(cell+Vector2i.ONE*radius)
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1): bump(Vector2i(x,y))

func _index_path(cell: Vector2i) -> void:
	var key := WorldState.chunk_of(cell)
	if not path_regions.has(key): path_regions[key] = {}
	path_regions[key][cell] = true

func _wear(world, cell: Vector2i, link: int) -> void:
	var key := WorldState.chunk_of(cell)
	if paths.has(cell):
		var present: Dictionary = paths[cell]
		if int(present.tick) == world.ticks or (present.wear == MAX_WEAR and world.ticks-int(present.tick) < MONTH):
			var joined := int(present.links)|link
			if joined != present.links and stage(int(present.wear)) > 0: bump(key)
			present.links = joined; present.tick = world.ticks
			return
	if not world.chunks.has(key) or int(world.chunks[key].tiles[WorldState.local_index(cell)]) not in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST,WorldState.Terrain.SAND]: return
	if not paths.has(cell):
		if paths.size() >= MAX_PATHS: return
		paths[cell] = {"wear":0,"tick":world.ticks,"links":0}
		_index_path(cell)
	var value: Dictionary = paths[cell]
	var before := stage(wear_at(value,world.ticks))
	var old_links := int(value.links)
	value.wear = mini(MAX_WEAR,wear_at(value,world.ticks)+1)
	value.tick = world.ticks; value.links = old_links|link
	var after := stage(value.wear)
	if before != after or (after > 0 and old_links != value.links): bump(key)

func moved(world, member: Dictionary, previous: Vector2i) -> void:
	var cell := Vector2i(member.x,member.y)
	var direction := cell-previous
	var index := WorldState.DIRECTIONS.find(direction)
	if index < 0: return
	_wear(world,previous,1<<index)
	_wear(world,cell,1<<(index^1))

func remove_path(cell: Vector2i) -> void:
	if not paths.has(cell): return
	paths.erase(cell)
	var key := WorldState.chunk_of(cell)
	path_regions[key].erase(cell)
	if path_regions[key].is_empty(): path_regions.erase(key)
	bump(key)

func site(cell: Vector2i, kind: String) -> void:
	var key := WorldState.chunk_of(cell)
	if not site_regions.has(key): site_regions[key] = {}
	site_regions[key][cell] = kind; bump(key)

func remove_site(cell: Vector2i, kind: String = "") -> void:
	var key := WorldState.chunk_of(cell)
	if not site_regions.has(key): return
	if not kind.is_empty() and site_regions[key].get(cell,"") != kind: return
	if not site_regions[key].erase(cell): return
	if site_regions[key].is_empty(): site_regions.erase(key)
	bump(key)

func clear_cell(cell: Vector2i, region: Vector2i = WorldState.NO_CELL) -> void:
	if paths.is_empty() and scars.is_empty(): return
	var key := WorldState.chunk_of(cell) if region == WorldState.NO_CELL else region
	if path_regions.has(key): remove_path(cell)
	if not scar_regions.has(key): return
	for y in range(cell.y-4,cell.y+1):
		for x in range(cell.x-4,cell.x+1):
			var origin := Vector2i(x,y)
			if scars.has(origin) and Rect2i(origin,Vector2i.ONE*int(scars[origin].size)).has_point(cell): remove_scar(origin)

func _index_scar(cell: Vector2i, extent: int) -> void:
	var low := WorldState.chunk_of(cell)
	var high := WorldState.chunk_of(cell+Vector2i.ONE*(extent-1))
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key := Vector2i(x,y)
			if not scar_regions.has(key): scar_regions[key] = {}
			scar_regions[key][cell] = true; bump(key)

func remove_scar(cell: Vector2i) -> void:
	var value: Dictionary = scars[cell]
	var low := WorldState.chunk_of(cell)
	var high := WorldState.chunk_of(cell+Vector2i.ONE*(int(value.size)-1))
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key := Vector2i(x,y)
			scar_regions[key].erase(cell)
			if scar_regions[key].is_empty(): scar_regions.erase(key)
			bump(key)
	scars.erase(cell)

func scar(world, cell: Vector2i, kind: String, extent: int = 1) -> void:
	if not scars.has(cell) and scars.size() >= MAX_SCARS: return
	if scars.has(cell): remove_scar(cell)
	scars[cell] = {"kind":kind,"size":extent,"tick":world.ticks}
	_index_scar(cell,extent)

func building(world, value: Dictionary, add: bool = true) -> void:
	if not GROUNDS.has(value.kind): return
	var cell := Vector2i(value.x,value.y)
	var radius: int = int(WorldEconomy.SIZE[value.kind])+int(GROUNDS[value.kind])
	var low := WorldState.chunk_of(cell-Vector2i.ONE*int(GROUNDS[value.kind]))
	var high := WorldState.chunk_of(cell+Vector2i.ONE*radius)
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key := Vector2i(x,y)
			if add:
				if not grounds.has(key): grounds[key] = {}
				grounds[key][value.id] = value
			elif grounds.has(key):
				grounds[key].erase(value.id)
				if grounds[key].is_empty(): grounds.erase(key)
			bump(key)
	if add:
		for point in scars.keys():
			if WorldEconomy.footprint(value).intersects(Rect2i(point,Vector2i.ONE*int(scars[point].size))):
				remove_scar(point)

func age_path(world, cell: Vector2i) -> void:
	if not paths.has(cell): return
	var value: Dictionary = paths[cell]
	var wear := wear_at(value,world.ticks)
	if wear == 0: remove_path(cell)
	elif stage(wear) != stage(wear_at(value,world.ticks-MONTH)): bump(WorldState.chunk_of(cell))

func age_scar(world, cell: Vector2i) -> void:
	if not scars.has(cell): return
	var value: Dictionary = scars[cell]
	var age: int = world.ticks-int(value.tick)
	if age >= WorldLife.YEAR*(2 if value.kind == "burn" else 4):
		remove_scar(cell)
	elif age/(WorldLife.YEAR/2) != maxi(0,age-MONTH)/(WorldLife.YEAR/2): invalidate_area(cell,value.size+1)

func save() -> Dictionary:
	var rows: Array = []
	for cell in paths:
		var value: Dictionary = paths[cell]
		rows.append([cell.x,cell.y,value.wear,value.tick,value.links])
	var remains: Array = []
	for cell in scars:
		var value: Dictionary = scars[cell]
		remains.append([cell.x,cell.y,value.kind,value.size,value.tick])
	return {"paths":rows,"scars":remains}

func restore(world, data: Variant) -> bool:
	var terrain_cache := {}
	if data != null:
		if not data is Dictionary or not data.get("paths") is Array or not data.get("scars") is Array or data.paths.size() > MAX_PATHS or data.scars.size() > MAX_SCARS: return false
		for row in data.paths:
			if not row is Array or row.size() != 5: return false
			for value in row:
				if not WorldState._integer(value): return false
			if row[0] < -WorldState.COORD_LIMIT or row[1] < -WorldState.COORD_LIMIT or row[0] >= WorldState.COORD_LIMIT or row[1] >= WorldState.COORD_LIMIT: return false
			var cell := Vector2i(row[0],row[1]); var key := WorldState.chunk_of(cell)
			if not world.inside(cell) or not world.has_region(key) or paths.has(cell) or row[2] < 1 or row[2] > MAX_WEAR or row[3] < 0 or row[3] > world.ticks or row[4] < 1 or row[4] > 15: return false
			if _restored_terrain(world,cell,terrain_cache) not in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST,WorldState.Terrain.SAND]: return false
			paths[cell] = {"wear":int(row[2]),"tick":int(row[3]),"links":int(row[4])}; _index_path(cell)
		for row in data.scars:
			if not row is Array or row.size() != 5 or row[2] not in ["ruin","burn"]: return false
			for index in [0,1,3,4]:
				if not WorldState._integer(row[index]): return false
			if row[0] < -WorldState.COORD_LIMIT or row[1] < -WorldState.COORD_LIMIT or row[0] >= WorldState.COORD_LIMIT or row[1] >= WorldState.COORD_LIMIT: return false
			var cell := Vector2i(row[0],row[1])
			if not world.inside(cell) or scars.has(cell) or row[3] < 1 or row[3] > 5 or row[4] < 0 or row[4] > world.ticks: return false
			if not world.inside(cell+Vector2i.ONE*(int(row[3])-1)) or _restored_terrain(world,cell,terrain_cache) not in [WorldState.Terrain.GRASS,WorldState.Terrain.SAND,WorldState.Terrain.FOREST]: return false
			scars[cell] = {"kind":row[2],"size":int(row[3]),"tick":int(row[4])}; _index_scar(cell,int(row[3]))
	for cell in world.stumps: site(cell,"stump")
	for cell in world.mineral_deposits: site(cell,"quarry")
	for value in world.buildings: building(world,value)
	return true

func _restored_terrain(world, cell: Vector2i, cache: Dictionary) -> int:
	var key := WorldState.chunk_of(cell)
	if not cache.has(key):
		var chunk: Dictionary = world.regions.snapshot(world,key)
		if chunk.is_empty(): return WorldState.Terrain.WATER
		cache[key] = chunk.tiles
	return int(cache[key][WorldState.local_index(cell)])
