class_name WorldPublicPlanJob
extends RefCounted

var world
var home: Dictionary
var nav: Dictionary
var cursor := 0
var kind := ""
var site: WorldSiteJob
var cells: Array = []
var anchor := WorldState.NO_CELL
var phase := 0
var finished := false

func _init(value, settlement: Dictionary) -> void:
	world = value; home = settlement
	nav = WorldEconomy.navigation(world,home)
	if WorldEconomy.food_days(world,home)<6: finished = true

func choose() -> String:
	var count := WorldEconomy.members(world,home).size()
	for option in ["irrigation","plaza","embankment","roadworks","mill","factory","power"]:
		if WorldEconomy.count(world,home,option,false)>0 or not world.networks.construction_ready(world,home,option): continue
		if option == "irrigation" and (nav.coasts.is_empty() or WorldEconomy.count(world,home,"farm") == 0): continue
		if option in ["plaza","roadworks"] and count < 12: continue
		if option == "embankment" and (nav.coasts.is_empty() or WorldEconomy.count(world,home,"dock")+WorldEconomy.count(world,home,"port") == 0): continue
		if option == "roadworks" and world.networks.neighbors.get(home.id,[]).is_empty(): continue
		return option
	return ""

func ready_materials(type: String) -> bool:
	return WorldEconomy.available_wood(world,home)>=int(WorldEconomy.COST[type]) and WorldCivilization.inputs_available(world,home,WorldCivilization.EXTRA.get(type,{})) and WorldDevelopment.construction_ready(world,home,type)

func unit() -> void:
	if finished: return
	if phase == 0:
		if world.networks.construction_ready(world,home,"bridge") and WorldEconomy.count(world,home,"bridge",false)<2 and ready_materials("bridge"): phase = 1
		else: phase = 2
		return
	if phase == 1:
		if cursor >= mini(96,nav.coasts.size()): phase = 2; cursor = 0; return
		var coast: Dictionary = nav.coasts[cursor]; cursor += 1
		var direction: Vector2i = coast.water-coast.land
		var span: Array = []
		if not WorldEconomy.valid_site(world,nav.parents,"bridge",coast.land): return
		for length in range(1,6):
			var cell: Vector2i = coast.land+direction*length
			if not world.inside(cell) or world.fires.has(cell) or world.occupied.has(cell) or world.networks.bridges.has(cell): return
			span.append([cell.x,cell.y])
			if world.terrain_at(cell) == WorldState.Terrain.WATER: continue
			if length<2 or not world.walkable(cell) or nav.parents.has(cell): return
			kind = "bridge"; anchor = coast.land; cells = span; phase = 4
			return
		return
	if phase == 2:
		kind = choose()
		if kind.is_empty() or not ready_materials(kind): finished = true; return
		site = WorldSiteJob.new(world,home,kind); phase = 3
		return
	if phase == 3:
		if not site.finished: site.unit(); return
		if site.result == WorldState.NO_CELL: finished = true; return
		anchor = site.result
		if kind == "roadworks":
			var candidates: Array = []
			for link in world.networks.neighbors.get(home.id,[]):
				if link.mode!= "land" or link.route.is_empty(): continue
				candidates = link.route; break
			var start: int = maxi(0,candidates.size()-32) if not candidates.is_empty() and Vector2i(candidates.back()[0],candidates.back()[1])==Vector2i(home.x,home.y) else 0
			for i in range(start,mini(candidates.size(),start+32)):
				var cell := Vector2i(candidates[i][0],candidates[i][1])
				if nav.parents.has(cell): cells.append([cell.x,cell.y])
			if cells.is_empty():
				for i in range(1,mini(25,nav.cells.size())): cells.append([nav.cells[i].x,nav.cells[i].y])
		phase = 4; return
	var building := WorldEconomy.add_building(world,home,kind,anchor)
	if not building.is_empty():
		building.project_cells = cells
		world.networks.state_for(world,home).project = kind
		world.log_event("Общественная стройка","%s: %s. Нужны материалы и работа жителей." % [home.name,WorldEconomy.NAMES[kind]])
	finished = true
