class_name WorldSiteJob
extends RefCounted

const DIRECTIONS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var world
var home: Dictionary
var kind: String
var center: Vector2i
var nav: Dictionary
var cursor := 0
var result := WorldState.NO_CELL
var finished := false
var signature: Array
var cache_key := ""
var ruin_cursor := 0

func _init(value, settlement: Dictionary, type: String) -> void:
	world = value; home = settlement; kind = type
	center = Vector2i(home.x, home.y)
	nav = WorldEconomy.navigation(world, home)
	if world.heritage.origin_index.get(home.id,{}).get("site",-1) == -1: ruin_cursor = WorldHeritage.FOOTPRINTS
	signature = [world.revision, world.buildings.size(), world.fires.size(), world.ticks if not world.fires.is_empty() else 0, nav.cells.size(),world.heritage.revision]
	cache_key = "%d:%s" % [home.id, kind]
	var cached: Dictionary = world.site_cache.get(cache_key, {})
	if cached.get("signature") == signature:
		if cached.cell == WorldState.NO_CELL or WorldEconomy.valid_site(world, nav.parents, kind, cached.cell): result = cached.cell; finished = true

func unit() -> void:
	if finished: return
	if ruin_cursor < WorldHeritage.FOOTPRINTS:
		var old: Vector2i = world.heritage.restoration(world,home,kind,nav,ruin_cursor); ruin_cursor += 1
		if old != WorldState.NO_CELL: result = old; _finish()
		return
	var cell: Vector2i
	if cursor < 13 * DIRECTIONS.size(): cell = center + DIRECTIONS[cursor % DIRECTIONS.size()] * (cursor / DIRECTIONS.size() + 3)
	else:
		var index := cursor - 13 * DIRECTIONS.size()
		if index >= nav.cells.size(): _finish(); return
		cell = nav.cells[index]
		if absi(cell.x - center.x) + absi(cell.y - center.y) < 3: cursor += 1; return
	cursor += 1
	if WorldEconomy.valid_site(world, nav.parents, kind, cell): result = cell; _finish()

func _finish() -> void:
	if world.site_cache.size() >= WorldState.MAX_BUILDINGS: world.site_cache.erase(world.site_cache.keys()[0])
	world.site_cache[cache_key] = {"signature": signature, "cell": result}
	finished = true
