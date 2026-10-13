class_name WorldNearestLandJob
extends RefCounted

var world
var origin: Vector2i
var radius := 12
var ring := 1
var x := -1
var y := -1
var result := WorldState.NO_CELL
var finished := false

func _init(value, center: Vector2i, reach: int = 12) -> void:
	world = value; origin = center; radius = reach
	if world.walkable(origin): result = origin; finished = true
	elif radius < 1: finished = true

func unit() -> void:
	if finished: return
	for i in 16:
		_test_cell()
		if finished: return

func _test_cell() -> void:
	var cell := origin+Vector2i(x,y)
	if world.walkable(cell): result = cell; finished = true; return
	if absi(y) == ring: x += 1
	elif x == -ring: x = ring
	else: x = ring+1
	if x > ring:
		y += 1; x = -ring
		if y > ring:
			ring += 1; x = -ring; y = -ring
			if ring > radius: finished = true
