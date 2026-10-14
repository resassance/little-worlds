class_name WorldFireStepJob
extends RefCounted

var world
var keys: Array
var spreading: Array[Vector2i] = []
var cursor := 0
var dirty := false
var finished := false
var spread_cursor := 0

func _init(value) -> void:
	world = value
	keys = world.fires.keys()

func unit() -> void:
	if finished: return
	if cursor >= keys.size():
		if spread_cursor < spreading.size():
			world.set_fire(spreading[spread_cursor]); spread_cursor += 1
		else: finished = true
		return
	var cell: Vector2i = keys[cursor]; cursor += 1
	var lifetime: int = WorldState.FOREST_FIRE_TICKS if world.terrain_at(cell) == WorldState.Terrain.FOREST else WorldState.GRASS_FIRE_TICKS
	world.fires[cell] = mini(int(world.fires[cell]),lifetime)-1
	world._set_food(cell, 0)
	if world.fires[cell] <= 0:
		world.erase_fire(cell)
		if world.terrain_at(cell) == WorldState.Terrain.FOREST:
			world._set_terrain(cell, WorldState.Terrain.GRASS)
			world._set_food(cell, 0)
			if world.stumps.size() < 4096: world.stumps[cell] = world.ticks; world.landscape.site(cell,"stump")
			world.landscape.scar(world,cell,"burn")
			dirty = true
		return
	if world.ticks < world.wet_until or world.rng.randf() > 0.08: return
	var target: Vector2i = cell + WorldState.DIRECTIONS[world.rng.randi_range(0, 3)]
	if world.inside(target) and world.terrain_at(target) in [WorldState.Terrain.GRASS, WorldState.Terrain.FOREST] and not world.fires.has(target) and not WorldWeather.wet(world, target): spreading.append(target)
