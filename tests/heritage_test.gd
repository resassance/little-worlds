extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func fixture() -> WorldState:
	return WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))

func historical_month(world: WorldState) -> int:
	var job := WorldHeritageJob.new(world)
	var maximum := 0
	while not job.finished:
		var before := Time.get_ticks_usec(); job.unit()
		maximum = maxi(maximum,Time.get_ticks_usec()-before)
	return maximum

func ruin(world: WorldState) -> Dictionary:
	var home: Dictionary = world.towns[0]
	world.heritage.origin(world,home)
	for i in range(world.people.size()-1,-1,-1):
		if world.people[i].home == home.id: world.remove_person(i,"голод")
	world.ticks += WorldEconomy.DAY_TICKS
	historical_month(world)
	check(not WorldEconomy.town(world,home.id).is_empty(),"empty settlement has a full month for returning residents")
	world.ticks += WorldEconomy.DAY_TICKS
	historical_month(world)
	world._repair_buildings()
	return world.heritage.sites[0]

func _initialize() -> void:
	var world := fixture()
	var original_rng := world.rng.state
	var site := ruin(world)
	check(WorldEconomy.town(world,13).is_empty(),"abandoned settlement leaves the active economy")
	check(site.name == "Ивовый берег" and site.periods[0].start == -1,"legacy settlement retains real name and unknown founding date")
	check(site.remains.size() > 10,"existing houses and workplaces leave foundations")
	check(site.ideas.size() == 3 and site.wood == 10,"real workshop knowledge and finite stock are retained")
	check(world.rng.state == original_rng,"history never consumes the simulation RNG")
	check(WorldAudit.conserved(world),"abandonment transfers stock without creating or deleting unaccounted resources")
	var old_id: int = site.id
	var point := Vector2i(site.x,site.y)
	var home: Dictionary = world.towns[0]
	var visitor: Dictionary = WorldEconomy.members(world,home)[0]
	WorldEconomy.lose_cargo(world,visitor)
	visitor.skills.build = 1000000
	visitor.ideas = []
	visitor.x = home.x; visitor.y = home.y
	visitor.task = WorldEconomy.task("visit",point)
	world.heritage.visit(world,visitor,point)
	check(site.visitors.size() == 1 and site.visitors[0].attempted == false,"ordinary visit discovers ruins without replacing working cargo")
	visitor.task = WorldEconomy.task("explore",point,home.id)
	visitor.task.phase = "outbound"; visitor.task.reason = "ruins"; visitor.task.surveyed = false
	visitor.task.radius = WorldExploration.state_for(world,home).radius
	visitor.x = point.x; visitor.y = point.y
	world.heritage.random.seed = 1
	world.heritage.visit(world,visitor,point)
	check(visitor.cargo > 0 and site.finds.size() == 2,"explorer takes finite physical cargo from former stocks")
	check(world.heritage.couriers.size() == 1,"an actual surviving record travels with its finder")
	var idea: String = world.heritage.couriers[0].idea
	check(not visitor.ideas.has(idea) or WorldSociety.get_society(world,home.id).tech[idea].known,"record does not grant a new idea while away")
	var inventory: int = visitor.cargo
	var remaining: Dictionary = site.stock.duplicate()
	for i in 40: world.heritage.visit(world,visitor,point)
	check(visitor.cargo == inventory and site.stock == remaining and site.finds.size() == 2,"repeated movement cannot farm the same finding")
	check(WorldAudit.conserved(world),"salvaged cargo remains conserved")
	WorldEconomy.set_task(world,visitor,{})
	visitor.skills.build = 200
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var fixture_file := FileAccess.open("res://artifacts/heritage-world.json",FileAccess.WRITE)
	fixture_file.store_string(JSON.stringify(saved)); fixture_file.close()
	var restored := WorldState.from_dict(saved)
	check(restored != null,"historical sites and carried records survive complete save validation")
	if restored == null: quit(1); return
	check(JSON.stringify(restored.heritage.save()) == JSON.stringify(world.heritage.save()),"history snapshot restores exactly")
	var loaded_visitor := WorldLife.person(restored,visitor.id)
	loaded_visitor.x = home.x; loaded_visitor.y = home.y
	restored.heritage.returned(restored,loaded_visitor)
	check(restored.heritage.couriers.is_empty() and loaded_visitor.ideas.has(idea),"record becomes personal knowledge only after returning home")
	check(WorldAudit.conserved(restored),"returning knowledge creates no physical resources")
	var captured := WorldSaveHeaderJob.new(world,[],true)
	while not captured.finished: captured.unit()
	var captured_history := JSON.stringify(captured.data.heritage)
	world.heritage.sites[0].wood -= 1; world.metrics.lost_wood += 1
	world.heritage.lost(visitor.id)
	check(JSON.stringify(captured.data.heritage) == captured_history,"background save owns independent history, stocks and couriers")
	for mutation in ["missing","null","duplicate","future","reserve","coordinates","idea","period","visitor","courier","link"]:
		var broken: Dictionary = saved.duplicate(true)
		match mutation:
			"missing": broken.erase("heritage")
			"null": broken.heritage = null
			"duplicate": broken.heritage.sites.append(broken.heritage.sites[0].duplicate(true))
			"future": broken.heritage.sites[0].periods[0].end = broken.ticks+1
			"reserve": broken.heritage.sites[0].wood = 13
			"coordinates": broken.heritage.sites[0].x = 1e30
			"idea": broken.heritage.sites[0].ideas = ["imaginary_technology"]
			"period": broken.heritage.sites[0].periods[0].end = -1
			"visitor": broken.heritage.sites[0].visitors[0].town = -1
			"courier": broken.heritage.couriers[0].member = -1
			"link": broken.heritage.origins[0].site = old_id
		check(WorldState.from_dict(broken) == null,"malformed history is rejected: "+mutation)
	var legacy: Dictionary = saved.duplicate(true); legacy.version = 11; legacy.erase("heritage")
	check(WorldState.from_dict(legacy) != null,"version 11 saves migrate without invented historical places")
	var surviving := fixture()
	surviving.ticks += WorldEconomy.DAY_TICKS
	historical_month(surviving)
	check(surviving.heritage.sites.is_empty(),"inhabited towns never turn into ruins")
	var new_home := {"id":restored.next_id,"name":"Новый очаг","x":point.x,"y":point.y,"food":0,"wood":0,"level":1}
	restored.next_id += 1; restored.towns.append(new_home)
	restored.heritage.settled(restored,new_home)
	WorldEconomy.add_building(restored,new_home,"camp",point,true)
	check(restored.heritage.sites[0].current == new_home.id and restored.heritage.sites[0].periods.size() == 2,"resettlement records a new living period without erasing the former one")
	var nav: Dictionary = WorldEconomy.navigation(restored,new_home)
	var chosen := WorldSiteJob.new(restored,new_home,"house")
	while not chosen.finished: chosen.unit()
	var matching := false
	for row in restored.heritage.sites[0].remains:
		if row[2] == "house" and chosen.result == Vector2i(row[0],row[1]): matching = true
	check(matching,"ordinary construction prefers a usable historical foundation")
	var house := WorldEconomy.add_building(restored,new_home,"house",chosen.result)
	check(not house.ready and house.delivered == 0 and house.work == 0,"historical restoration still requires all construction materials and work")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(restored.to_dict()))) != null,"resettled historical world loads with active-period references")
	var full := WorldState.from_dict(saved.duplicate(true))
	var sliced := WorldState.from_dict(saved.duplicate(true))
	for i in 30:
		full.step()
		var job := WorldStepJob.new(sliced)
		while not job.finished: job.advance(200)
	check(JSON.stringify(full.to_dict()) == JSON.stringify(sliced.to_dict()),"full and time-sliced simulation preserve identical discovery outcomes")
	world.ticks += WorldLife.YEAR*20
	check(world.heritage.sites.size() == 1,"historical sites persist beyond temporary landscape scars")
	var walking := WorldState.new()
	walking.paint(Vector2i.ZERO,35,WorldState.Terrain.GRASS)
	for i in 3: walking.add_person(Vector2i(i,0),false)
	walking._found_town(walking.people[0])
	var former: Dictionary = walking.towns[0]
	for member in walking.people: WorldEconomy.set_home(walking,member,former.id)
	for i in range(walking.people.size()-1,-1,-1): walking.remove_person(i,"голод")
	for month in 2:
		walking.ticks += WorldEconomy.DAY_TICKS; historical_month(walking)
	walking._repair_buildings()
	for i in 6: walking.add_person(Vector2i(12+i%3,i/3),false)
	walking._found_town(walking.people[0])
	var successor: Dictionary = walking.towns[0]
	for member in walking.people: WorldEconomy.set_home(walking,member,successor.id)
	successor.food = 40; walking.metrics.harvested_food += 40
	var scout: Dictionary = walking.people[0]
	walking.metrics.eaten_food += scout.rations; scout.rations = 0
	check(WorldExploration.assign_ruins(walking,scout,successor),"a fed community autonomously assigns a scout to accessible ruins")
	for i in 40:
		if scout.task.is_empty(): break
		WorldEconomy.execute(walking,scout,successor)
	check(walking.heritage.sites[0].visitors.size() == 1 and walking.heritage.sites[0].visitors[0].attempted,"real outbound movement discovers and studies the site")
	check(scout.task.is_empty() and Vector2i(scout.x,scout.y) == Vector2i(successor.x,successor.y),"the scout completes a real return route")
	check(WorldAudit.conserved(walking),"an autonomous archaeological trip preserves resource balances")
	var lost_world := WorldState.from_dict(saved.duplicate(true))
	var finder := WorldLife.person(lost_world,visitor.id)
	lost_world.remove_person(lost_world.people.find(finder),"голод")
	check(lost_world.heritage.couriers.is_empty(),"death removes a carried record without teaching it to the settlement")
	check(lost_world.heritage.sites[0].finds.back().status == "lost","lost records remain recorded as losses in local history")
	var drowned := fixture()
	var drowned_home: Dictionary = drowned.towns[0]
	var drowned_point := Vector2i(drowned_home.x,drowned_home.y)
	drowned.paint(drowned_point,0,WorldState.Terrain.WATER)
	check(drowned.heritage.sites.size() == 1 and drowned.heritage.sites[0].periods.back().cause == "Потеря земли","terrain destruction records its actual cause")
	check(not drowned.heritage.sites[0].remains.is_empty(),"terrain repair captures surviving historical footprints before deleting buildings")
	check(WorldAudit.conserved(drowned),"loss of settlement terrain conserves reserves, displaced residents and lost goods")
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(drowned.to_dict()))) != null,"submerged historical places remain valid after saving")
	print("Heritage: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
