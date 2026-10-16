class_name WorldLandworksJob
extends RefCounted

var world
var cursor := 0
var home: Dictionary = {}
var state: Dictionary = {}
var nav: Dictionary = {}
var modes: Array[String] = []
var checked := 0
var finished := false

func _init(value) -> void:
	world = value

func _next() -> void:
	home = {}; state = {}; nav = {}; modes.clear(); checked = 0
	cursor += 1

func unit() -> void:
	if finished: return
	if cursor>=world.towns.size(): finished = true; return
	if home.is_empty():
		home = world.towns[cursor]
		state = WorldLandworks.state_for(world,home)
		if not state.project.is_empty() and state.project.ready:
			WorldLandworks.apply(world,home); _next(); return
		if world.ticks%WorldEconomy.DAY_TICKS!=0 or not state.project.is_empty() or world.ticks<state.next_tick: _next(); return
		nav = world.navigation.get(home.id,{})
		if nav.is_empty() or WorldEconomy.food_days(world,home)<8: _next(); return
		var count := WorldEconomy.members(world,home).size()
		if nav.wood.size()<maxi(12,count*2) and home.wood<24: modes.append("forest")
		if nav.food.size()<maxi(36,count*5): modes.append("cultivate")
		if nav.cells.size()<maxi(96,count*12): modes.append_array(["pass","reclaim"])
		for i in range(modes.size()-1,-1,-1):
			var spec: Dictionary = WorldLandworks.SPEC[modes[i]]
			if not WorldLandworks.available(world,home,modes[i]) or not WorldCivilization.inputs_available(world,home,{spec.material:int(spec.cost)}): modes.remove_at(i)
		if modes.is_empty(): _next()
		return
	if checked>=mini(WorldLandworks.SEARCH_LIMIT,nav.cells.size()):
		state.next_tick = world.ticks+WorldEconomy.DAY_TICKS
		_next(); return
	var stand: Vector2i = nav.cells[int(state.cursor)%nav.cells.size()]
	state.cursor = (int(state.cursor)+1)%1000001; checked += 1
	for mode in modes:
		if mode in ["forest","cultivate"]:
			if WorldLandworks.suitable(world,home,mode,stand,stand,nav): _plan(mode,stand,stand); return
		else:
			for direction in WorldState.DIRECTIONS:
				var cell: Vector2i = stand+direction
				if WorldLandworks.suitable(world,home,mode,cell,stand,nav): _plan(mode,cell,stand); return

func _plan(mode: String, cell: Vector2i, stand: Vector2i) -> void:
	state.serial = mini(1000000000,int(state.serial)+1)
	state.project = {"mode":mode,"x":cell.x,"y":cell.y,"stand_x":stand.x,"stand_y":stand.y,"work":0,"ready":false}
	world.log_event("Освоение земли","%s: %s · участок (%d, %d)." % [home.name,WorldLandworks.SPEC[mode].name.to_lower(),cell.x,cell.y])
	_next()
