class_name WorldFireMeshJob
extends RefCounted

var world
var origin: Vector2i
var low: Vector2i
var high: Vector2i
var regions: Array
var region_cursor := 0
var cells: Array = []
var cursor := 0
var span := 1
var groups: Dictionary = {}
var buffer := PackedFloat32Array()
var revision := 0
var finished := false

func _init(value, camera: Vector2i, first: Vector2i, last: Vector2i, grouping: int) -> void:
	world = value; origin = camera; low = first; high = last; span = grouping
	regions = world.fire_regions.keys(); revision = world.fire_revision

func advance(budget_usec: int = 500) -> bool:
	var deadline := Time.get_ticks_usec()+budget_usec
	while not finished:
		unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func unit() -> void:
	if cursor < cells.size():
		var cell: Vector2i = cells[cursor]; cursor += 1
		if not world.fires.has(cell) or cell.x < low.x or cell.y < low.y or cell.x > high.x or cell.y > high.y: return
		var group := Vector2i(floori(float(cell.x)/span),floori(float(cell.y)/span))
		if groups.has(group): return
		groups[group] = true
		var center := Vector2(cell-origin)*WorldView.TILE+Vector2(4,-3)
		var scale := minf(4.0,sqrt(float(span)))
		buffer.append_array(PackedFloat32Array([scale,0,0,center.x,0,scale,0,center.y,float(posmod(hash(cell),4)),2,0,0]))
	elif region_cursor < regions.size():
		var key: Vector2i = regions[region_cursor]; region_cursor += 1
		var region_low := key*WorldState.CHUNK_SIZE
		if region_low.x > high.x or region_low.y > high.y or region_low.x+WorldState.CHUNK_SIZE <= low.x or region_low.y+WorldState.CHUNK_SIZE <= low.y: return
		cells = world.fire_regions.get(key,{}).keys(); cursor = 0
	else: finished = true
