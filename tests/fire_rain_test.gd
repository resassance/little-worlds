extends SceneTree

var failures := 0
var maximum := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: "+description)

func fire_tick(world: WorldState) -> void:
	world.ticks += 1
	var job := WorldFireStepJob.new(world)
	while not job.finished:
		var start := Time.get_ticks_usec()
		job.unit()
		maximum = maxi(maximum,Time.get_ticks_usec()-start)

func _initialize() -> void:
	var world := WorldState.new()
	world.paint(Vector2i.ZERO,32,WorldState.Terrain.FOREST)
	world.ignite(Vector2i.ZERO,24)
	check(world.fire_regions.size() == 4,"fire index includes negative and positive chunk boundaries")
	world.wet_until = 1000
	var initial := world.fires.size()
	for i in WorldState.FOREST_FIRE_TICKS: fire_tick(world)
	check(world.fires.is_empty() and world.fire_regions.is_empty(),"forest fire and its spatial index expire within twelve ticks")
	check(world.terrain_at(Vector2i.ZERO) == WorldState.Terrain.GRASS and world.food_at(Vector2i.ZERO) == 0,"burnt forest loses its trees and food")
	world.ignite(Vector2i.ZERO,8)
	for i in WorldState.GRASS_FIRE_TICKS: fire_tick(world)
	check(world.fires.is_empty(),"grass fire expires within eight ticks")
	world.set_fire(Vector2i.ZERO,24)
	for i in WorldState.GRASS_FIRE_TICKS: fire_tick(world)
	check(world.fires.is_empty(),"saved fires with old lifetimes finish at the shorter terrain-specific lifetime")
	world.ignite(Vector2i.ZERO,8)
	world.rain(Vector2i(-2,0),2)
	check(not world.fires.has(Vector2i(-2,0)) and world.fires.has(Vector2i(6,0)),"rain removes fire inside its footprint and preserves fire outside it")
	check(world.wet_until-world.ticks == WorldState.RAIN_TICKS,"rain protection lasts twenty ticks without a sixty-tick tail")
	check(world.food_at(Vector2i(-2,0)) == world.capacity(world.terrain_at(Vector2i(-2,0))),"rain restores food immediately")
	for key in world.fire_regions:
		for cell in world.fire_regions[key]: check(world.fires.has(cell) and WorldState.chunk_of(cell) == key,"indexed fire belongs to its actual chunk")
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict(),"",true,true)))
	check(loaded != null and loaded.fire_regions == world.fire_regions,"loading reconstructs the derived fire index without save-format changes")
	var mesh := WorldFireMeshJob.new(world,Vector2i.ZERO,Vector2i(-4,-4),Vector2i(4,4),1)
	while not mesh.finished: mesh.advance(500)
	check(mesh.buffer.size()/12 < world.fires.size(),"fire rendering visits and renders only the visible footprint")
	var sparse := WorldState.new()
	for i in 1000:
		var cell := Vector2i(i*64,0)
		sparse._set_terrain(cell,WorldState.Terrain.GRASS); sparse.set_fire(cell)
	var accesses := sparse.regions.clock
	var nearby := WorldFireMeshJob.new(sparse,Vector2i.ZERO,Vector2i(-8,-8),Vector2i(8,8),1)
	while not nearby.finished: nearby.advance(500)
	check(nearby.buffer.size() == 12 and sparse.regions.clock == accesses,"offscreen fires do not load distant land to render one nearby flame")
	check(maximum < 4000,"fire spreading and expiry each yield before a whole fire front is processed")
	print("Fire and rain: initial %d, largest unit %.2f ms, failures %d" % [initial,maximum/1000.0,failures])
	quit(1 if failures else 0)
