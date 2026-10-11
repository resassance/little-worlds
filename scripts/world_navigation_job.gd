class_name WorldNavigationJob
extends RefCounted

var world
var home: Dictionary
var origin: Vector2i
var head := 0
var finished := false
var result: Dictionary
var reach := WorldEconomy.RANGE

func _init(value, settlement: Dictionary) -> void:
	world = value; home = settlement
	reach = WorldExploration.radius(home)
	origin = Vector2i(home.x, home.y)
	if world.navigation.has(home.id):
		result = world.navigation[home.id]; finished = true
	else:
		var cells: Array[Vector2i] = [origin]
		var food: Array[Vector2i] = []
		var wood: Array[Vector2i] = []
		var quarries: Array[Dictionary] = []
		var coasts: Array[Dictionary] = []
		result = {"parents":{origin:origin},"distances":{origin:0},"cells":cells,"food":food,"wood":wood,"quarries":quarries,"coasts":coasts,"routes":{},"order":{origin:0}}

func advance(budget_usec: int = 1000) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func unit() -> void:
	if finished: return
	if head >= result.cells.size():
		world.navigation[home.id] = result
		finished = true
		return
	var cell: Vector2i = result.cells[head]; head += 1
	var terrain: int = world.terrain_at(cell)
	if terrain in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST]: result.food.append(cell)
	if terrain == WorldState.Terrain.FOREST: result.wood.append(cell)
	for direction in WorldState.DIRECTIONS:
		var other: Vector2i = cell + direction
		var ground: int = world.terrain_at(other)
		if ground == WorldState.Terrain.MOUNTAIN: result.quarries.append({"land":cell,"rock":other})
		if ground == WorldState.Terrain.WATER: result.coasts.append({"land":cell,"water":other})
		if result.parents.has(other) or absi(other.x-origin.x)+absi(other.y-origin.y)>reach: continue
		if ground in [WorldState.Terrain.WATER,WorldState.Terrain.MOUNTAIN] or not world.inside(other): continue
		result.parents[other] = cell
		result.distances[other] = int(result.distances[cell]) + 1
		result.order[other] = result.cells.size()
		result.cells.append(other)
