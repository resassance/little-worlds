class_name WorldLandscapeJob
extends RefCounted

var world
var paths: Array
var scars: Array
var stumps: Array
var cursor := 0
var phase := 0
var finished := false

func _init(value) -> void:
	world = value
	finished = world.ticks%WorldEconomy.DAY_TICKS != 0
	if finished: return
	paths = world.landscape.paths.keys(); scars = world.landscape.scars.keys(); stumps = world.stumps.keys()

func unit() -> void:
	if finished: return
	for i in 8:
		if phase == 0:
			if cursor >= paths.size(): phase = 1; cursor = 0; return
			world.landscape.age_path(world,paths[cursor]); cursor += 1
		elif phase == 1:
			if cursor >= scars.size(): phase = 2; cursor = 0; return
			world.landscape.age_scar(world,scars[cursor]); cursor += 1
		else:
			if cursor >= stumps.size(): finished = true; return
			var cell: Vector2i = stumps[cursor]; cursor += 1
			if not world.stumps.has(cell): continue
			var age: int = world.ticks-int(world.stumps[cell])
			if age/WorldLife.YEAR != maxi(0,age-WorldEconomy.DAY_TICKS)/WorldLife.YEAR: world.landscape.bump(WorldState.chunk_of(cell))
