class_name WorldTravelPathJob
extends RefCounted

const SEARCH_LIMIT := 8192
var world
var start: Vector2i
var finish: Vector2i
var key: Vector4i
var heap: Array[Vector4i] = []
var parents: Dictionary = {}
var costs: Dictionary = {}
var cursor := 0
var result: Array = []
var finished := false

func _init(value, origin: Vector2i, target: Vector2i) -> void:
	world = value; start = origin; finish = target
	key = Vector4i(start.x,start.y,finish.x,finish.y)
	if not world.walkable(start) or not world.walkable(finish): finished = true; return
	if world.travel_path_revision != world.path_revision:
		world.travel_paths.clear(); world.travel_path_revision = world.path_revision
	if world.fires.is_empty() and world.travel_paths.has(key):
		result = world.travel_paths[key]; finished = true; return
	parents[start] = start; costs[start] = 0
	_push(start,0)

func advance(budget_usec: int = 1000) -> bool:
	var deadline := Time.get_ticks_usec()+budget_usec
	while not finished:
		unit()
		if budget_usec>0 and Time.get_ticks_usec()>=deadline: break
	return finished

func _less(a: Vector4i, b: Vector4i) -> bool:
	if a.z!=b.z: return a.z<b.z
	if a.w!=b.w: return a.w>b.w
	return a.y<b.y if a.y!=b.y else a.x<b.x

func _push(cell: Vector2i, cost: int) -> void:
	var row := Vector4i(cell.x,cell.y,cost+absi(cell.x-finish.x)+absi(cell.y-finish.y),cost)
	heap.append(row)
	var i := heap.size()-1
	while i>0:
		var parent := (i-1)/2
		if not _less(row,heap[parent]): break
		heap[i] = heap[parent]; i = parent
	heap[i] = row

func _pop() -> Vector4i:
	var first := heap[0]
	var row: Vector4i = heap.pop_back()
	if heap.is_empty(): return first
	var i := 0
	while i*2+1<heap.size():
		var child := i*2+1
		if child+1<heap.size() and _less(heap[child+1],heap[child]): child += 1
		if not _less(heap[child],row): break
		heap[i] = heap[child]; i = child
	heap[i] = row
	return first

func unit() -> void:
	if finished: return
	if heap.is_empty() or costs.size()>SEARCH_LIMIT: _complete(false); return
	var row := _pop()
	var point := Vector2i(row.x,row.y)
	if row.w!=int(costs[point]): return
	cursor += 1
	if point==finish: _complete(true); return
	if row.w>=WorldTravel.MAX_PATH-1: return
	for direction in WorldState.DIRECTIONS:
		var next: Vector2i = point+direction
		var cost := row.w+1
		if int(costs.get(next,2147483647))<=cost or not world.walkable(next) or world.fires.has(next): continue
		costs[next] = cost; parents[next] = point; _push(next,cost)

func _complete(found: bool) -> void:
	finished = true
	if found:
		var point := finish
		result.append([point.x,point.y])
		while point!=start:
			point = parents[point]; result.append([point.x,point.y])
		result.reverse()
	if world.travel_paths.size()<64 and world.fires.is_empty(): world.travel_paths[key] = result
