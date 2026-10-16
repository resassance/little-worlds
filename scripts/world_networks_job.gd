class_name WorldNetworksJob
extends RefCounted

var world
var cursor := 0
var phase := 0
var finished := false

func _init(value) -> void:
	world = value
	finished = world.ticks%WorldEconomy.DAY_TICKS != 0

func unit() -> void:
	if finished: return
	if phase == 0:
		if cursor >= world.towns.size(): phase = 1; cursor = world.networks.towns.size()-1; return
		var home: Dictionary = world.towns[cursor]; cursor += 1
		var state: Dictionary = world.networks.state_for(world,home)
		var count := WorldEconomy.members(world,home).size()
		var food := WorldEconomy.food_days(world,home)
		var crowded := count > WorldEconomy.housing(world,home)
		var disaster: bool = WorldWeather.at(world,Vector2i(home.x,home.y),"drought") or world.fires.has(Vector2i(home.x,home.y))
		state.pressure = clampi(int(state.pressure)+(8 if food<6 else 0)+(6 if crowded else 0)+(4 if disaster else 0)-(4 if food>=6 and not crowded and not disaster else 0),0,100)
		if WorldEconomy.count(world,home,"power") > 0 and WorldSociety.mastered(world,home,"electricity") and home.wood >= 2:
			WorldCivilization.consume(world,home,{"wood":2}); state.power_until = world.ticks+WorldEconomy.DAY_TICKS
			WorldSociety.use(world,home,"electricity")
		var stage := 1 if count >= 6 else 0
		if count >= 16 and WorldEconomy.count(world,home,"market") > 0: stage = 2
		if count >= 32 and WorldEconomy.count(world,home,"plaza") > 0 and WorldEconomy.count(world,home,"townhouse")+WorldEconomy.count(world,home,"apartment")>0: stage = 3
		if count >= 48 and WorldEconomy.count(world,home,"factory") > 0: stage = 4
		if count >= 96 and WorldEconomy.count(world,home,"tower") > 0 and world.networks.powered(world,home): stage = 5
		if state.stage != stage:
			state.stage = stage; world.networks.revision += 1
			world.log_event("Облик поселения","%s: %s." % [home.name,WorldNetworks.STAGES[stage]])
		return
	if phase == 1:
		if cursor < 0: phase = 2; cursor = world.networks.links.size()-1; return
		var state: Dictionary = world.networks.towns[cursor]; cursor -= 1
		if WorldEconomy.town(world,state.town).is_empty():
			world.networks.town_index.erase(state.town); world.networks.towns.erase(state)
		return
	if cursor < 0: finished = true; return
	var link: Dictionary = world.networks.links[cursor]; cursor -= 1
	var a := WorldEconomy.town(world,link.a)
	var b := WorldEconomy.town(world,link.b)
	if a.is_empty() or b.is_empty():
		world.networks.link_index.erase(world.networks.pair(link.a,link.b)); world.networks.links.erase(link)
		world.networks.neighbors.get(link.a,[]).erase(link); world.networks.neighbors.get(link.b,[]).erase(link)
		return
	if world.ticks%(WorldEconomy.DAY_TICKS*3) != 0: return
	if a.wood < 4 and b.wood < 4 and world.navigation.has(a.id) and world.navigation.has(b.id):
		var overlap := false
		var wood: Array = world.navigation[a.id].wood
		for i in mini(8,wood.size()):
			if world.navigation[b.id].parents.has(wood[i]): overlap = true; break
		if overlap:
			link.trust = maxi(0,int(link.trust)-6); link.reason = "Спор за доступный лес"
			if link.trust < 30: link.blocked_until = world.ticks+WorldEconomy.DAY_TICKS*3
	elif WorldEconomy.food_days(world,a)>=6 and WorldEconomy.food_days(world,b)>=6:
		link.trust = mini(100,int(link.trust)+1)
