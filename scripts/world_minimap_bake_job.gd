class_name WorldMinimapBakeJob
extends RefCounted

var world
var image: Image
var bounds: Rect2i
var revision: int
var keys: Array
var cursor := 0
var tile_cursor := 0
var chunk: Dictionary = {}
var key := Vector2i.ZERO
var origin := Vector2.ZERO
var scale_value := Vector2.ONE
var finished := false

func _init(value) -> void:
	world = value
	revision = world.revision
	bounds = world.land_bounds()
	keys = world.region_keys()
	image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(WorldView.COLORS[0])
	scale_value = Vector2(image.get_size()) / Vector2(bounds.size)

func advance(budget_usec: int = 500) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func unit() -> void:
	if cursor >= keys.size(): finished = true; return
	if tile_cursor == 0:
		key = keys[cursor]
		origin = Vector2(key * WorldState.CHUNK_SIZE - bounds.position) * scale_value
		var extent := Vector2.ONE * WorldState.CHUNK_SIZE * scale_value
		if maxf(extent.x, extent.y) <= 2.0:
			if world.region_bounds.has(key): image.fill_rect(Rect2i(Vector2i(origin), Vector2i(extent).max(Vector2i.ONE)), WorldView.COLORS[WorldState.Terrain.GRASS])
			cursor += 1
			return
		chunk = world.regions.get_region(world, key)
		if chunk.is_empty(): cursor += 1; return
	var terrain: int = chunk.tiles[tile_cursor]
	if terrain != WorldState.Terrain.WATER:
		var cell := Vector2i(tile_cursor % WorldState.CHUNK_SIZE, tile_cursor / WorldState.CHUNK_SIZE)
		var point := origin + Vector2(cell) * scale_value
		var extent := Vector2i(ceili(scale_value.x), ceili(scale_value.y)).max(Vector2i.ONE)
		image.fill_rect(Rect2i(Vector2i(point), extent), WorldView.COLORS[terrain])
	tile_cursor += 1
	if tile_cursor == WorldState.CHUNK_SIZE * WorldState.CHUNK_SIZE:
		tile_cursor = 0; cursor += 1
