class_name WorldFaunaMeshJob
extends RefCounted

const CAPACITY := 512
var world: WorldState
var origin: Vector2i
var low: Vector2i
var high: Vector2i
var cursor := 0
var count := 0
var buffer := PackedFloat32Array()
var finished := false
var groups: Array

func _init(value: WorldState, camera: Vector2i, first: Vector2i, last: Vector2i) -> void:
	world = value; origin = camera; low = first; high = last
	groups = world.fauna.herds.duplicate()
	buffer.resize(CAPACITY*12)

func advance(budget_usec: int = 200) -> bool:
	var deadline := Time.get_ticks_usec()+budget_usec
	while not finished:
		unit()
		if budget_usec>0 and Time.get_ticks_usec()>=deadline: break
	return finished

func unit() -> void:
	if cursor>=groups.size() or count>=CAPACITY: finished = true; return
	var herd: Dictionary = groups[cursor]; cursor += 1
	if herd.x<low.x or herd.y<low.y or herd.x>high.x or herd.y>high.y: return
	var cell := Vector2i(herd.x,herd.y)
	var base := Vector2(cell-origin)*8+Vector2(4,1)
	for i in mini(4,int(herd.count)):
		if count>=CAPACITY: break
		var at := count*12
		var place := base+Vector2((i%2)*10-5,(i/2)*7-3)
		buffer[at] = 0.65; buffer[at+5] = 0.65
		buffer[at+3] = place.x; buffer[at+7] = place.y
		buffer[at+8] = float(WorldFauna.SPEC[herd.species].sprite)
		buffer[at+9] = float(posmod(int(herd.id)+i,2))
		buffer[at+10] = 1.0; buffer[at+11] = 1.0
		count += 1
