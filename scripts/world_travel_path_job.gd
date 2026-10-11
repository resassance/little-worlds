class_name WorldTravelPathJob
extends RefCounted

var world
var start: Vector2i
var finish: Vector2i
var key: Vector4i
var queue: Array[Vector2i] = []
var parents: Dictionary = {}
var cursor := 0
var result: Array = []
var finished := false

func _init(value, origin: Vector2i, target: Vector2i) -> void:
	world = value; start = origin; finish = target
	key = Vector4i(start.x,start.y,finish.x,finish.y)
	if not world.walkable(start) or not world.walkable(finish): finished = true; return
	if world.travel_path_revision != world.revision:
		world.travel_paths.clear(); world.travel_path_revision = world.revision
	if world.fires.is_empty() and world.travel_paths.has(key):
		result = world.travel_paths[key]; finished = true; return
	queue.append(start); parents[start] = start

func advance(budget_usec: int = 1000) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func unit() -> void:
	if finished: return
	if cursor >= queue.size() or parents.size() > 8192: _complete(); return
	var point := queue[cursor]; cursor += 1
	if point == finish: _complete(); return
	for direction in WorldState.DIRECTIONS:
		var next: Vector2i = point + direction
		if parents.has(next) or not world.walkable(next) or world.fires.has(next): continue
		parents[next] = point; queue.append(next)

func _complete() -> void:
	finished = true
	if parents.has(finish):
		var point := finish
		result.append([point.x,point.y])
		while point != start:
			point = parents[point]; result.append([point.x,point.y])
			if result.size() > WorldTravel.MAX_PATH: result.clear(); break
		result.reverse()
	if world.travel_paths.size() < 64 and world.fires.is_empty(): world.travel_paths[key] = result
