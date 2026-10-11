class_name WorldSeaSegmentJob
extends RefCounted

var world
var a: Vector2i
var delta: Vector2
var keys: Array
var cursor := 0
var sample_cursor := 0
var sample_count := 0
var start := 0.0
var end := 1.0
var sampling := false
var clear := true
var finished := false

func _init(value, first: Vector2i, last: Vector2i, regions: Array = []) -> void:
	world = value; a = first; delta = Vector2(last - first)
	keys = world.region_keys() if regions.is_empty() else regions

func unit() -> void:
	if finished: return
	if sampling:
		var point := Vector2i((Vector2(a) + delta * lerpf(start, end, float(sample_cursor) / sample_count)).floor())
		if world.terrain_at(point) != WorldState.Terrain.WATER:
			clear = false; finished = true; return
		sample_cursor += 1
		if sample_cursor > sample_count: sampling = false
		return
	if cursor >= keys.size(): finished = true; return
	var key: Vector2i = keys[cursor]; cursor += 1
	var low := Vector2(key * WorldState.CHUNK_SIZE)
	var high := low + Vector2.ONE * WorldState.CHUNK_SIZE
	start = 0.0; end = 1.0
	for axis in 2:
		if absf(delta[axis]) < 0.0001:
			if a[axis] < low[axis] or a[axis] >= high[axis]: return
		else:
			var t0: float = (low[axis] - a[axis]) / delta[axis]
			var t1: float = (high[axis] - a[axis]) / delta[axis]
			start = maxf(start, minf(t0, t1))
			end = minf(end, maxf(t0, t1))
	if start > end: return
	sample_count = maxi(1, ceili(delta.length() * (end - start) * 2))
	sample_cursor = 0; sampling = true
