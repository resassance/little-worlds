class_name WorldTravelDailyJob
extends RefCounted

var world
var grid: Dictionary = {}
var cursor := 0
var home_cursor := 0
var visited := 0
var searches := 0
var bucket_cursor := 0
var candidate_cursor := 0
var member_cursor := 0
var phase := -1
var candidates: Array[Dictionary] = []
var residents: Array[Dictionary] = []
var target: Dictionary = {}
var migrating := false
var purpose := ""
var path_job: WorldTravelPathJob
var colony_job: WorldColonySearchJob
var finished := false

func _init(value) -> void:
	world = value
	finished = world.ticks%WorldEconomy.DAY_TICKS != 0

func _next_home() -> void:
	home_cursor = (home_cursor+1)%maxi(1,world.towns.size()); visited += 1; phase = 0; cursor = 0; bucket_cursor = 0; candidate_cursor = 0; member_cursor = 0
	candidates.clear(); residents.clear(); target = {}; path_job = null; colony_job = null

func group_for(home: Dictionary, colony: bool = false) -> Array:
	if member_cursor >= residents.size(): return []
	var member: Dictionary = residents[member_cursor]; member_cursor += 1
	if not WorldLife.adult(world,member) or WorldTravel.away(world,member.id) or member.cargo>0 or (not migrating and not colony and member.task.get("kind","") in ["care","teach","research"]): return []
	if not migrating and not colony: return [int(member.id)]
	var family := WorldLife.household(world,member.household)
	var group: Array = family.members.duplicate() if not family.is_empty() else [int(member.id)]
	if colony and group.size()<3:
		for i in mini(16,residents.size()):
			var other: Dictionary = residents[(member_cursor+i)%residents.size()]
			if not WorldLife.adult(world,other) or group.has(int(other.id)) or WorldTravel.away(world,other.id): continue
			var other_family := WorldLife.household(world,other.household)
			var additions: Array = other_family.members if not other_family.is_empty() else [int(other.id)]
			if group.size()+additions.size()>8: continue
			for id in additions:
				if not group.has(id): group.append(id)
			if group.size()>=3: break
	return group

func unit() -> void:
	if finished: return
	if phase == -1:
		if cursor >= world.towns.size(): phase = 0; home_cursor = (world.ticks/WorldEconomy.DAY_TICKS)%maxi(1,world.towns.size()); cursor = 0; return
		var home: Dictionary = world.towns[cursor]; cursor += 1
		var key := WorldState.chunk_of(Vector2i(home.x,home.y))
		if not grid.has(key): grid[key] = []
		grid[key].append(home)
		return
	if visited>=world.towns.size() or (phase==0 and searches>=4): finished = true; return
	var home: Dictionary = world.towns[home_cursor]
	if phase == 0:
		for journey in world.journeys:
			if journey.home == home.id: _next_home(); return
		if WorldEconomy.members(world,home).size()<5: _next_home(); return
		residents = WorldEconomy.members(world,home).duplicate()
		var state: Dictionary = world.networks.state_for(world,home)
		migrating = state.pressure>=12 or residents.size()>WorldEconomy.housing(world,home)
		bucket_cursor = int(state.neighbor_cursor); state.neighbor_cursor = (bucket_cursor+17)%81
		phase = 1; cursor = 0
		return
	if phase == 1:
		if cursor >= 81: phase = 2; cursor = 0; return
		var index := (bucket_cursor+cursor)%81; cursor += 1
		var key := WorldState.chunk_of(Vector2i(home.x,home.y))+Vector2i(index%9-4,index/9-4)
		for other in grid.get(key,[]):
			if other.id == home.id or candidates.size()>=8: continue
			if Vector2i(home.x,home.y).distance_squared_to(Vector2i(other.x,other.y))<=128*128: candidates.append(other)
		return
	if phase == 2:
		if candidate_cursor >= candidates.size():
			var state: Dictionary = world.networks.state_for(world,home)
			if migrating and state.pressure>=24 and world.ticks>=state.next_migration and WorldEconomy.food_days(world,home)>=4:
				colony_job = WorldColonySearchJob.new(world,home,grid); searches += 1; phase = 5
			else: _next_home()
			return
		var other: Dictionary = candidates[candidate_cursor]; candidate_cursor += 1
		purpose = "migrate" if migrating else "trade"
		if migrating:
			if WorldEconomy.housing(world,other)-WorldEconomy.members(world,other).size()<2 or WorldEconomy.food_days(world,other)<WorldEconomy.food_days(world,home)+2 or not world.networks.permitted(home.id,other.id,world.ticks): return
		else:
			var offer: Dictionary = world.networks.offer(world,home,other)
			if offer.is_empty(): return
			purpose = "aid" if offer.aid else "trade"
			if purpose == "trade" and WorldEconomy.count(world,home,"market")==0: return
		searches += 1
		target = other; path_job = WorldTravelPathJob.new(world,Vector2i(home.x,home.y),Vector2i(other.x,other.y)); phase = 3
		return
	if phase == 3:
		if not path_job.finished: path_job.unit(); return
		if path_job.result.is_empty(): phase = 2; return
		phase = 4; member_cursor = 0
		return
	if phase == 4:
		if member_cursor >= residents.size(): phase = 2; return
		var group := group_for(home)
		if group.is_empty(): return
		if WorldTravel.launch(world,home,target,group,purpose,path_job.result): _next_home()
		return
	if phase == 5:
		if not colony_job.finished: colony_job.unit(); return
		var state: Dictionary = world.networks.state_for(world,home)
		state.next_migration = world.ticks+WorldEconomy.DAY_TICKS*6
		if colony_job.result == WorldState.NO_CELL: _next_home(); return
		target = {"id":-1,"x":colony_job.result.x,"y":colony_job.result.y,"name":"Новый очаг"}
		path_job = WorldTravelPathJob.new(world,Vector2i(home.x,home.y),colony_job.result); phase = 6
		return
	if phase == 6:
		if not path_job.finished: path_job.unit(); return
		if path_job.result.is_empty(): _next_home(); return
		phase = 7; member_cursor = 0
		return
	if member_cursor >= residents.size(): _next_home(); return
	var group := group_for(home,true)
	if group.size()<3: return
	if WorldTravel.launch(world,home,target,group,"colony",path_job.result): _next_home()
