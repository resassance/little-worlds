class_name WorldSculpt
extends RefCounted

var world: WorldState
var center: Vector2i
var dimensions: Vector2i
var origin: Vector2i
var cursor := 0
var total := 0
var finished := false
var cancelled := false
var terrain := WorldState.Terrain.GRASS

func begin(value: WorldState, point: Vector2i, span: Vector2i, ground: int) -> bool:
	if span.x < 32 or span.y < 32 or span.x > 2048 or span.y > 2048 or ground not in [WorldState.Terrain.GRASS,WorldState.Terrain.FOREST]: return false
	world=value; center=point; dimensions=span; origin=point-span/2; terrain=ground
	if not world.inside(origin) or not world.inside(origin+span-Vector2i.ONE): return false
	var low:=WorldState.chunk_of(origin); var high:=WorldState.chunk_of(origin+span-Vector2i.ONE)
	var needed:=0
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			if not world.has_region(Vector2i(x,y)): needed+=1
	if world.region_count()+needed>WorldState.MAX_CHUNKS: return false
	total=span.x*span.y
	return true

func advance(budget_usec: int = 4000) -> void:
	if finished: return
	if cancelled or world.regions.failed:
		complete(); return
	var deadline:=Time.get_ticks_usec()+budget_usec
	while cursor<total and Time.get_ticks_usec()<deadline:
		var cell:=origin+Vector2i(cursor%dimensions.x,cursor/dimensions.x)
		cursor+=1
		var distance:=Vector2(cell-center)/Vector2(dimensions)*2
		if distance.length_squared()>1 or world.terrain_at(cell)!=WorldState.Terrain.WATER: continue
		var ground:=terrain
		var detail:=posmod(hash(Vector3i(cell.x,cell.y,world.world_seed)),100)
		if distance.length_squared()>.92: ground=WorldState.Terrain.SAND
		elif detail<3: ground=WorldState.Terrain.MOUNTAIN
		elif detail<20: ground=WorldState.Terrain.FOREST
		world._set_terrain(cell,ground)
	world.regions.trim(world,WorldState.chunk_of(origin+Vector2i(cursor%dimensions.x,cursor/dimensions.x)),1)
	world.terrain_changed.emit()
	if cursor>=total: complete()

func complete() -> void:
	finished=true
	world.population_dirty=true
	world.regions.trim(world,WorldState.NO_CELL,4)
	world.terrain_changed.emit()
	world.changed.emit()
	world.log_event("Создана суша","%s. Размер области: %d × %d клеток." % ["Создание остановлено, готовая земля сохранена" if cancelled else "Новый материк готов",dimensions.x,dimensions.y])
