class_name WorldColonySearchJob
extends RefCounted

var world
var grid: Dictionary
var home: Dictionary
var origin: Vector2i
var queue: Array[Vector2i] = []
var seen: Dictionary = {}
var cursor := 0
var result := WorldState.NO_CELL
var finished := false

func _init(value, settlement: Dictionary, towns_grid: Dictionary) -> void:
	world = value; home = settlement; grid = towns_grid; origin = Vector2i(home.x,home.y)
	queue.append(origin); seen[origin] = true

func unit() -> void:
	if finished: return
	if cursor >= queue.size() or seen.size() > 4096: finished = true; return
	var cell := queue[cursor]; cursor += 1
	var distance := absi(cell.x-origin.x)+absi(cell.y-origin.y)
	if distance >= 32 and world.terrain_at(cell) in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST] and not world.fires.has(cell) and not world.occupied.has(cell):
		var near := false
		for dy in range(-1,2):
			for dx in range(-1,2):
				for other in grid.get(WorldState.chunk_of(cell)+Vector2i(dx,dy),[]):
					if cell.distance_squared_to(Vector2i(other.x,other.y))<28*28: near = true; break
		if not near:
			var fertile := 0
			for direction in WorldState.DIRECTIONS:
				for reach in [1,3,5]:
					var point: Vector2i = cell+direction*reach
					if world.terrain_at(point) in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST] and not world.fires.has(point): fertile += 1
			if fertile >= 8: result = cell; finished = true; return
	if distance >= 64: return
	for direction in WorldState.DIRECTIONS:
		var next: Vector2i = cell+direction
		if seen.has(next) or not world.walkable(next) or world.fires.has(next): continue
		seen[next] = true; queue.append(next)
