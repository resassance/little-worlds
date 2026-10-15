class_name WorldHeritageJob
extends RefCounted

var world
var cursor := 0
var phase := -1
var pending: Array[Dictionary] = []
var by_town: Dictionary = {}
var population: Dictionary = {}
var draw_keys: Array = []
var finished := false

func _init(value) -> void:
	world = value
	finished = world.ticks%WorldEconomy.DAY_TICKS != 0

func unit() -> void:
	if finished: return
	match phase:
		-1:
			if cursor >= world.people.size(): phase = 0; cursor = 0; return
			var member: Dictionary = world.people[cursor]; cursor += 1
			population[member.home] = int(population.get(member.home,0))+1
		0:
			if cursor >= world.towns.size(): phase = 1 if not pending.is_empty() else 3; cursor = 0; return
			var home: Dictionary = world.towns[cursor]; cursor += 1
			var state: Dictionary = world.heritage.origin(world,home)
			if int(population.get(home.id,0)) > 0: state.empty = -1; state.cause = "Поселение опустело"; return
			if state.empty == -1: state.empty = world.ticks; return
			if world.ticks-state.empty >= WorldEconomy.DAY_TICKS: pending.append(home); by_town[home.id] = []
		1:
			if cursor >= world.buildings.size(): phase = 2; cursor = 0; return
			var value: Dictionary = world.buildings[cursor]; cursor += 1
			if by_town.has(value.town) and value.ready:
				world.heritage.remember_building(world,value)
		2:
			if cursor >= pending.size(): phase = 3; cursor = 0; return
			var home: Dictionary = pending[cursor]; cursor += 1
			world.heritage.abandon(world,home,str(world.heritage.origin_index[home.id].cause))
			world.metrics.lost_food += int(home.food); world.metrics.lost_wood += int(home.wood)
			var stock: Dictionary = world.civilization.get(home.id,{}).get("stock",{})
			for key in stock: world.industry.lost[key] += int(stock[key])
			world.civilization.erase(home.id)
			WorldExploration.forget(world,home)
			world.towns.erase(home)
			var society: Dictionary = world.society_index.get(home.id,{})
			world.societies.erase(society); world.society_index.erase(home.id)
			world.heritage.forget_origin(home)
			world.navigation.erase(home.id); world.society_cache.erase(home.id)
			world.population.town_count = -1
		3:
			if cursor == 0:
				draw_keys = world.heritage.draw_regions.keys() if world.ticks%WorldLife.YEAR == 0 else []
			if cursor >= draw_keys.size(): finished = true; return
			world.landscape.bump(draw_keys[cursor]); cursor += 1
