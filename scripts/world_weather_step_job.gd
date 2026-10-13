class_name WorldWeatherStepJob
extends RefCounted

var world
var phase := 0
var cursor := 0
var cell_index := 0
var event: Dictionary = {}
var finished := false

func _init(value) -> void:
	world = value

func unit() -> void:
	if finished: return
	if phase == 0:
		if cursor < world.weather.active.size():
			var existing: Dictionary = world.weather.active[cursor]
			if int(existing.until) <= world.ticks:
				world.log_event("Погода наладилась", "Явление «%s» завершилось в области %d, %d." % [WorldWeather.TITLES[existing.kind], existing.x, existing.y])
				world.weather.active.remove_at(cursor)
			else: cursor += 1
			return
		phase = 1; cursor = 0; return
	if phase == 1:
		if int(world.weather.rate) > 0 and world.ticks >= int(world.weather.next_tick): WorldWeather.schedule(world)
		phase = 2; return
	if event.is_empty():
		if cursor >= world.weather.active.size(): finished = true; return
		var candidate: Dictionary = world.weather.active[cursor]
		cursor += 1
		if world.ticks < int(candidate.pulse): return
		candidate.pulse = world.ticks + 8
		if candidate.kind == "thunder":
			var target := Vector2i(candidate.x, candidate.y) + Vector2i(WorldWeather.index(world, candidate.radius * 2 + 1) - int(candidate.radius), WorldWeather.index(world, candidate.radius * 2 + 1) - int(candidate.radius))
			if world.inside(target) and WorldWeather.contains(candidate, target) and world.terrain_at(target) in [WorldState.Terrain.GRASS, WorldState.Terrain.FOREST] and world.ticks >= world.wet_until and not WorldWeather.wet(world, target):
				world.set_fire(target)
				candidate.strike_tick = world.ticks; candidate.strike_x = target.x; candidate.strike_y = target.y
			return
		if candidate.kind == "frost": return
		event = candidate; cell_index = 0
	var width := int(event.radius) * 2 + 1
	if cell_index >= width * width: event = {}; return
	var cell := Vector2i(event.x, event.y) + Vector2i(cell_index % width - int(event.radius), cell_index / width - int(event.radius))
	cell_index += 1
	if not world.inside(cell) or not WorldWeather.contains(event, cell): return
	if event.kind in ["rain", "storm"]: world.erase_fire(cell)
	if world.terrain_at(cell) not in [WorldState.Terrain.GRASS, WorldState.Terrain.FOREST]: return
	var before: int = world.food_at(cell)
	var after := maxi(0, before - 1) if event.kind == "drought" else mini(world.capacity(world.terrain_at(cell)), before + 1)
	if before != after: world._set_food(cell, after)
