class_name WorldLandscapeBakeJob
extends RefCounted

const TILE := 8
var world: WorldState
var coord: Vector2i
var revision: int
var terrain_revision: int
var image: Image
var tiles := PackedInt32Array()
var buildings: Array
var paths: Array
var sites: Array
var scars: Array
var phase := 0
var cursor := 0
var finished := false

func _init(value: WorldState, key: Vector2i) -> void:
	world = value; coord = key
	revision = int(world.landscape.versions.get(key,0)); terrain_revision = int(world.revisions.get(key,0))
	image = Image.create(WorldState.CHUNK_SIZE*TILE,WorldState.CHUNK_SIZE*TILE,false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT)
	var chunk := world.regions.snapshot(world,key)
	if not chunk.is_empty(): tiles = chunk.tiles
	buildings = world.landscape.grounds.get(key,{}).values()
	paths = world.landscape.path_regions.get(key,{}).keys()
	sites = world.landscape.site_regions.get(key,{}).keys()
	scars = world.landscape.scar_regions.get(key,{}).keys()

func advance(budget_usec: int = 400) -> bool:
	var deadline := Time.get_ticks_usec()+budget_usec
	while not finished:
		_unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func _unit() -> void:
	var items: Array = [buildings,scars,paths,sites][phase]
	if cursor >= items.size():
		phase += 1; cursor = 0
		if phase == 4: finished = true
		return
	var value: Variant = items[cursor]; cursor += 1
	match phase:
		0: _ground(value)
		1: _scar(value)
		2: _path(value)
		3: _site(value)

func _terrain(cell: Vector2i) -> int:
	if tiles.is_empty() or WorldState.chunk_of(cell) != coord: return WorldState.Terrain.WATER
	return int(tiles[WorldState.local_index(cell)])

func _pos(cell: Vector2i) -> Vector2i:
	return (cell-coord*WorldState.CHUNK_SIZE)*TILE

func _rect(pos: Vector2i, extent: Vector2i, color: Color) -> void:
	var area := Rect2i(pos,extent).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if area.has_area(): image.fill_rect(area,color)

func _ground(value: Dictionary) -> void:
	if not world.building_index.has(value.id): return
	var footprint := WorldEconomy.footprint(value)
	var margin: int = int(WorldLandscape.GROUNDS[value.kind])
	var area := footprint.grow(margin).intersection(Rect2i(coord*WorldState.CHUNK_SIZE,Vector2i.ONE*WorldState.CHUNK_SIZE))
	var soil := Color("aa9574")
	if value.kind in ["forge","kiln","workshop"]: soil = Color("8e8676")
	elif value.kind in ["market","council","school","archive"]: soil = Color("c0ae8a")
	elif value.kind == "farm": soil = Color("9b8561")
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var cell := Vector2i(x,y)
			if _terrain(cell) not in [WorldState.Terrain.GRASS,WorldState.Terrain.SAND]: continue
			var dx := maxi(maxi(footprint.position.x-x,x-footprint.end.x+1),0)
			var dy := maxi(maxi(footprint.position.y-y,y-footprint.end.y+1),0)
			if dx*dx+dy*dy > margin*margin: continue
			var position := _pos(cell)
			var detail := posmod(hash(Vector3i(x,y,world.world_seed)),37)
			var ground_color: Color = WorldView.COLORS[_terrain(cell)]
			if _terrain(cell) == WorldState.Terrain.GRASS:
				var biome := WorldClimate.biome(world,cell)
				if biome > 0: ground_color = WorldClimate.COLORS[biome]
			var color := soil.lerp(ground_color,0.42 if dx+dy > 0 else 0.08)
			color.a = 250.0/255.0
			_rect(position,Vector2i(8,8),color)
			_rect(position+Vector2i(2,5),Vector2i(2,1),color.darkened(0.1))

func _path(cell: Vector2i) -> void:
	if not world.landscape.paths.has(cell) or _terrain(cell) not in [WorldState.Terrain.GRASS,WorldState.Terrain.SAND,WorldState.Terrain.FOREST]: return
	var value: Dictionary = world.landscape.paths[cell]
	var stage := WorldLandscape.stage(WorldLandscape.wear_at(value,world.ticks))
	if stage == 0: return
	var position := _pos(cell)
	var width := stage
	var color := Color("b5a27a") if stage == 3 else (Color("a3916e") if stage == 2 else Color("98a06c"))
	if stage == 1 and _terrain(cell) == WorldState.Terrain.GRASS:
		var biome := WorldClimate.biome(world,cell)
		if biome > 0: color = WorldClimate.COLORS[biome].darkened(0.15)
	color.a = 250.0/255.0
	var start := 4-width/2
	_rect(position+Vector2i(start,start),Vector2i.ONE*width,color)
	for i in 4:
		if (int(value.links)&(1<<i)) == 0: continue
		var origin := Vector2i(start,start)
		var extent := Vector2i.ONE*width
		if i == 0: origin.x = 0; extent.x = start+width
		elif i == 1: extent.x = TILE-start
		elif i == 2: origin.y = 0; extent.y = start+width
		else: extent.y = TILE-start
		_rect(position+origin,extent,color)
	if stage == 3: _rect(position+Vector2i(3,3),Vector2i(2,2),color.lightened(0.08))

func _site(cell: Vector2i) -> void:
	var position := _pos(cell)
	if world.stumps.has(cell) and _terrain(cell) == WorldState.Terrain.GRASS and world.building_at(cell).is_empty():
		_rect(position+Vector2i(1,5),Vector2i(6,2),Color("7a7456"))
		_rect(position+Vector2i(2,3),Vector2i(4,3),Color("876247"))
		_rect(position+Vector2i(2,3),Vector2i(4,1),Color("d8b980"))
		_rect(position+Vector2i(3,3),Vector2i(2,1),Color("a97d51"))
		if world.climate.forest_regrowth and WorldClimate.biome(world,cell) not in [1,4,5] and world.ticks-int(world.stumps[cell]) >= WorldLife.YEAR:
			_rect(position+Vector2i(6,3),Vector2i(1,3),Color("876e46"))
			_rect(position+Vector2i(4,2),Vector2i(4,2),Color("63965b"))
			_rect(position+Vector2i(5,1),Vector2i(2,1),Color("a5ba6a"))
	elif world.mineral_deposits.has(cell) and _terrain(cell) == WorldState.Terrain.MOUNTAIN:
		var remaining: int = int(world.mineral_deposits[cell])
		var depth := 3 if remaining == 0 else (2 if remaining <= 12 else 1)
		_rect(position+Vector2i(0,2),Vector2i(8,5),Color("7a7668"))
		for row in depth:
			_rect(position+Vector2i(row,3+row),Vector2i(8-row*2,1),Color("494f4d"))
		_rect(position+Vector2i(1,2),Vector2i(6,1),Color("c1b7a0"))
		if remaining > 0: _rect(position+Vector2i(5,4),Vector2i(2,1),Color("9e7d5d"))

func _scar(cell: Vector2i) -> void:
	if not world.landscape.scars.has(cell): return
	var value: Dictionary = world.landscape.scars[cell]
	var age := clampf(float(world.ticks-value.tick)/(WorldLife.YEAR*4),0.0,1.0)
	var extent: int = int(value.size)
	for y in extent:
		for x in extent:
			var point := cell+Vector2i(x,y)
			if _terrain(point) not in [WorldState.Terrain.GRASS,WorldState.Terrain.SAND]: continue
			var position := _pos(point)
			var color := Color("696f54") if value.kind == "burn" else Color("8b826b")
			color = color.lerp(WorldView.COLORS[_terrain(point)],age*0.65)
			_rect(position+Vector2i(1,1),Vector2i(6,6),color)
			_rect(position+Vector2i(2,4),Vector2i(4,1),color.darkened(0.23))
			if value.kind == "ruin":
				_rect(position+Vector2i(1,1),Vector2i(2,3),Color("c6b190").lerp(color,age))
				_rect(position+Vector2i(5,3),Vector2i(2,2),Color("a29b82"))
