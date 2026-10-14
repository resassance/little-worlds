class_name WorldBrushJob
extends RefCounted

var world
var command: Dictionary
var center: Vector2i
var distance := 0
var step := 0
var radius := 0
var row := 0
var column := 0
var spans: Array[Vector2i] = []
var span_cursor := 0
var coverage: Dictionary
var mode: String
var terrain := -1
var biome := -1
var phase := 0
var keys: Array[Vector2i] = []
var touched: Dictionary = {}
var key_cursor := 0
var additional := 0
var changed := false
var terrain_dirty := false
var rejected := false
var finished := false
var cells_written := 0
var previews: Dictionary = {}
var history_region := WorldState.NO_CELL
var history_present := false

func _init(value, edit: Dictionary) -> void:
	world = value; command = edit; mode = edit.tool; radius = edit.radius; coverage = edit.coverage
	previews = edit.get("previews", {})
	terrain = {"water":0,"sand":1,"grass":2,"forest":3,"mountain":4}.get(mode, -1)
	if mode.begins_with("biome_"): biome = int(mode.trim_prefix("biome_"))
	if mode == "fire": radius = mini(radius, 8)
	if mode == "rain": radius = mini(radius, 8) + 3
	distance = maxi(absi(edit.finish.x-edit.start.x), absi(edit.finish.y-edit.start.y))
	_begin_stamp()

func _begin_stamp() -> void:
	center = Vector2i(Vector2(command.start).lerp(Vector2(command.finish), 0.0 if distance == 0 else float(step)/distance).round())
	row = -radius; spans.clear(); span_cursor = 0; additional = 0; keys.clear(); key_cursor = 0
	phase = 0 if terrain > 0 or biome >= 0 else 1
	if terrain > 0:
		var low := WorldState.chunk_of(center-Vector2i.ONE*radius)
		var high := WorldState.chunk_of(center+Vector2i.ONE*radius)
		for y in range(low.y, high.y+1):
			for x in range(low.x, high.x+1): keys.append(Vector2i(x,y))

func _next_stamp() -> void:
	step += 1
	if step > distance: finished = true
	else: _begin_stamp()

func _row_span() -> Vector2i:
	var width := floori(sqrt(float(radius*radius-row*row)))
	return Vector2i(maxi(center.x-width, -WorldState.COORD_LIMIT), mini(center.x+width, WorldState.COORD_LIMIT-1))

func _uncovered_row() -> Array[Vector2i]:
	var incoming := _row_span()
	var result: Array[Vector2i] = []
	var left := incoming.x
	for interval in coverage.get(center.y+row,[]):
		if interval.y < left: continue
		if interval.x > incoming.y: break
		if interval.x > left: result.append(Vector2i(left,mini(incoming.y,interval.x-1)))
		left = maxi(left,interval.y+1)
	if left <= incoming.y: result.append(Vector2i(left,incoming.y))
	return result

func _take_row() -> void:
	var y := center.y+row
	var incoming := _row_span()
	var old: Array = coverage.get(y, [])
	spans = _uncovered_row(); span_cursor = 0
	var merged: Array[Vector2i] = []
	var inserted := false
	for interval in old:
		if interval.y+1 < incoming.x: merged.append(interval)
		elif incoming.y+1 < interval.x:
			if not inserted: merged.append(incoming); inserted = true
			merged.append(interval)
		else: incoming = Vector2i(mini(incoming.x,interval.x), maxi(incoming.y,interval.y))
	if not inserted: merged.append(incoming)
	coverage[y] = merged
	if not spans.is_empty(): column = spans[0].x

func unit() -> void:
	if finished: return
	if world.regions.failed: rejected = true; finished = true; return
	if phase == 0:
		if terrain > 0:
			if key_cursor < keys.size():
				var key := keys[key_cursor]; key_cursor += 1
				var low := key*WorldState.CHUNK_SIZE
				var near := Vector2i(clampi(center.x,low.x,low.x+WorldState.CHUNK_SIZE-1),clampi(center.y,low.y,low.y+WorldState.CHUNK_SIZE-1))
				if world.inside(near) and near.distance_squared_to(center) <= radius*radius and not world.has_region(key): additional += 1
				return
			if world.region_count()+additional > WorldState.MAX_CHUNKS: rejected = true; finished = true; return
		elif biome >= 0:
			if row <= radius:
				if spans.is_empty():
					spans = _uncovered_row(); span_cursor = 0
					if spans.is_empty(): row += 1; return
					column = spans[0].x
				var cell := Vector2i(column,center.y+row); column += 1
				if world.inside(cell) and world.walkable(cell) and not world.biome_overrides.has(cell): additional += 1
				if column > spans[span_cursor].y:
					span_cursor += 1
					if span_cursor >= spans.size(): row += 1; spans.clear()
					else: column = spans[span_cursor].x
				return
			if world.biome_overrides.size()+additional > 65536: rejected = true; finished = true; return
		phase = 1; row = -radius; spans.clear(); return
	if row > radius: _next_stamp(); return
	if spans.is_empty():
		_take_row()
		if spans.is_empty(): row += 1
		return
	var cell := Vector2i(column,center.y+row)
	column += 1
	if column > spans[span_cursor].y:
		span_cursor += 1
		if span_cursor >= spans.size(): spans.clear(); row += 1
		else: column = spans[span_cursor].x
	if not world.inside(cell): return
	if terrain >= 0:
		var key := WorldState.chunk_of(cell)
		if history_region != key:
			history_region = key
			history_present = world.landscape.path_regions.has(key) or world.landscape.scar_regions.has(key)
		var previous: int = world.terrain_at(cell)
		world._set_terrain(cell,terrain); world.erase_fire(cell)
		if history_present and terrain not in [WorldState.Terrain.WATER,WorldState.Terrain.MOUNTAIN]: world.landscape.clear_cell(cell,key)
		touched[key] = true
		terrain_dirty = terrain_dirty or previous != terrain; changed = true; cells_written += 1
		if previous != terrain: _preview(cell,terrain)
	elif biome >= 0:
		if world.walkable(cell) and int(world.biome_overrides.get(cell,-1)) != biome:
			world._grow(world.regions.get_region(world,WorldState.chunk_of(cell)))
			world.biome_overrides[cell] = biome
			world.touch_terrain(cell,0,false)
			changed = true; cells_written += 1
			_preview(cell,world.terrain_at(cell))
	elif mode == "fire":
		if world.terrain_at(cell) in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST]:
			world.set_fire(cell); changed = true; cells_written += 1
	elif mode == "rain":
		world.erase_fire(cell); world._set_food(cell,world.capacity(world.terrain_at(cell)))
		changed = true; cells_written += 1

func _preview(cell: Vector2i, ground: int) -> void:
	var key := WorldState.chunk_of(cell)
	if not previews.has(key):
		var image := Image.create(WorldState.CHUNK_SIZE,WorldState.CHUNK_SIZE,false,Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		previews[key] = {"pixels":image,"texture":null,"dirty":true,"revision":world.revisions.get(key,0)}
	var patch: Dictionary = previews[key]
	var color: Color = WorldView.COLORS[ground]
	if ground in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST]:
		var climate := WorldClimate.biome(world,cell)
		if climate != 0: color = WorldClimate.COLORS[climate].darkened(0.12 if ground == WorldState.Terrain.FOREST else 0.0)
		if climate in [0,3,4,5]: color.a = 250.0 / 255.0
	patch.pixels.set_pixel(posmod(cell.x,WorldState.CHUNK_SIZE),posmod(cell.y,WorldState.CHUNK_SIZE),color)
	patch.dirty = true; patch.revision = int(world.revisions.get(key,0))
