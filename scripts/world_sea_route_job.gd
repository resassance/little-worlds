class_name WorldSeaRouteJob
extends RefCounted

const CACHE_LIMIT := 128
var world
var a: Vector2i
var b: Vector2i
var cache_key: Vector4i
var keys: Array
var routing_keys: Array = []
var segment: WorldSeaSegmentJob
var vertices: Array[Vector2i] = []
var distances := {0: 0.0}
var parents: Dictionary = {}
var done: Dictionary = {}
var cursor := 0
var phase := 0
var current := -1
var edge_cursor := 0
var best := INF
var result: Array = []
var finished := false
var corridor: Rect2i
var expanded := false

func _init(value, first: Vector2i, last: Vector2i) -> void:
	world = value; a = first; b = last
	cache_key = Vector4i(a.x, a.y, b.x, b.y)
	if world.sea_routes.has(cache_key):
		result = world.sea_routes[cache_key].duplicate(true)
		finished = true
		return
	keys = world.region_keys()
	corridor = Rect2i(Vector2i(mini(a.x,b.x),mini(a.y,b.y))-Vector2i.ONE*64,Vector2i(absi(a.x-b.x)+129,absi(a.y-b.y)+129))
	vertices = [a, b]
	segment = WorldSeaSegmentJob.new(world, a, b, keys)

func advance(budget_usec: int = 1000) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func _finish() -> void:
	if result.is_empty() and not expanded:
		expanded = true; cursor = 0; phase = 1
		vertices = [a,b]; distances = {0:0.0}; parents.clear(); done.clear(); segment = null; routing_keys.clear()
		return
	if world.sea_routes.size() >= CACHE_LIMIT: world.sea_routes.erase(world.sea_routes.keys()[0])
	world.sea_routes[cache_key] = result.duplicate(true)
	finished = true

func unit() -> void:
	if finished: return
	match phase:
		0:
			if not segment.finished: segment.unit(); return
			if segment.clear: result = [[a.x, a.y], [b.x, b.y]]; _finish()
			else: phase = 1; segment = null
		1:
			if cursor >= keys.size(): phase = 2; return
			var key: Vector2i = keys[cursor]; cursor += 1
			if expanded or corridor.grow(36).intersects(Rect2i(key*WorldState.CHUNK_SIZE,Vector2i.ONE*WorldState.CHUNK_SIZE)): routing_keys.append(key)
			if vertices.size() >= 126: return
			if not expanded and not corridor.intersects(Rect2i(key*WorldState.CHUNK_SIZE-Vector2i(2,2),Vector2i(36,36))): return
			var low := key * WorldState.CHUNK_SIZE - Vector2i(2, 2)
			var high := low + Vector2i(35, 35)
			for point in [low, Vector2i(high.x, low.y), high, Vector2i(low.x, high.y)]:
				if world.inside(point) and world.terrain_at(point) == WorldState.Terrain.WATER: vertices.append(point)
		2:
			current = -1; best = INF
			for index in distances:
				var estimate: float = distances[index]+vertices[index].distance_to(b)
				if not done.has(index) and estimate < best: best = estimate; current = index
			if current == -1: _finish(); return
			best = distances[current]
			if current == 1:
				if not parents.has(1): _finish(); return
				result = [[b.x, b.y]]; cursor = 1; phase = 4; return
			done[current] = true
			edge_cursor = 0; phase = 3
		3:
			if edge_cursor >= vertices.size(): phase = 2; return
			var index := edge_cursor
			var score := best + vertices[current].distance_to(vertices[index])
			if segment != null:
				if not segment.finished: segment.unit(); return
				if segment.clear: distances[index] = score; parents[index] = current
				segment = null; edge_cursor += 1
			elif index == current or done.has(index) or score >= distances.get(index, INF): edge_cursor += 1
			else: segment = WorldSeaSegmentJob.new(world, vertices[current], vertices[index], routing_keys)
		4:
			if cursor == 0: _finish(); return
			cursor = parents[cursor]
			result.push_front([vertices[cursor].x, vertices[cursor].y])
