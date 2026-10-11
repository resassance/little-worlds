class_name WorldTravelDailyJob
extends RefCounted

var world
var home_cursor := 0
var target_cursor := 0
var member_cursor := 0
var residents: Array[Dictionary] = []
var migrating := false
var path_job: WorldTravelPathJob
var phase := 0
var finished := false

func _init(value) -> void:
	world = value
	finished = world.ticks % (WorldEconomy.DAY_TICKS * 6) != 0

func _next_home() -> void:
	home_cursor += 1; target_cursor = 0; phase = 0
	residents.clear(); path_job = null

func unit() -> void:
	if finished: return
	if home_cursor >= world.towns.size(): finished = true; return
	var home: Dictionary = world.towns[home_cursor]
	if phase == 0:
		for journey in world.journeys:
			if journey.home == home.id: _next_home(); return
		residents = WorldEconomy.members(world, home).duplicate()
		if residents.size() < 5: _next_home(); return
		phase = 1
		return
	if target_cursor >= world.towns.size(): _next_home(); return
	var target: Dictionary = world.towns[target_cursor]
	if phase == 1:
		if target.id == home.id or Vector2i(home.x,home.y).distance_squared_to(Vector2i(target.x,target.y)) > 128*128: target_cursor += 1; return
		migrating = WorldEconomy.food_days(world,home) < 4 or WorldEconomy.members(world,home).size() > WorldEconomy.housing(world,home)
		if migrating and WorldEconomy.housing(world,target) <= WorldEconomy.members(world,target).size(): target_cursor += 1; return
		if migrating and WorldEconomy.food_days(world,target) <= WorldEconomy.food_days(world,home)+2: target_cursor += 1; return
		if not migrating and WorldEconomy.count(world,home,"market") == 0: target_cursor += 1; return
		path_job = WorldTravelPathJob.new(world,Vector2i(home.x,home.y),Vector2i(target.x,target.y))
		phase = 2
		return
	if phase == 2:
		if not path_job.finished: path_job.unit(); return
		residents = WorldEconomy.members(world,home).duplicate()
		member_cursor = 0; phase = 3
		return
	if member_cursor >= residents.size():
		if not world.journeys.is_empty() and world.journeys.back().home == home.id: _next_home()
		else: target_cursor += 1; phase = 1
		return
	var member: Dictionary = residents[member_cursor]; member_cursor += 1
	if not WorldLife.adult(world,member) or WorldTravel.away(world,member.id) or member.cargo > 0 or member.task.get("kind","") in ["teach","care","research"]: return
	var group: Array = [int(member.id)]
	if migrating:
		var family := WorldLife.household(world,member.household)
		if not family.is_empty(): group = family.members.duplicate()
	elif not WorldLife.care_candidate(world,member).is_empty(): return
	if WorldTravel.launch(world,home,target,group,"migrate" if migrating else "trade",path_job.result):
		_next_home()
