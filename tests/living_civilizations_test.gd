extends "res://tests/expansion_test.gd"

func stock(world: WorldState, settlement: Dictionary, kind: String, amount: int) -> void:
	var before := world.networks.amount(world,settlement,kind)
	world.networks.put(world,settlement,kind,amount-before)
	if kind=="food":
		if amount>=before: world.metrics.spawn_food += amount-before
		else: world.metrics.lost_food += before-amount
	elif kind=="wood":
		if amount>=before: world.metrics.harvested_wood += amount-before
		else: world.metrics.lost_wood += before-amount
	elif amount>=before: world.industry.produced[kind] += amount-before
	else: world.industry.lost[kind] += before-amount

func land_pair() -> WorldState:
	var world := WorldState.new()
	home(world,Vector2i.ZERO)
	home(world,Vector2i(50,0),3)
	for x in range(15,36): world.paint(Vector2i(x,0),2,WorldState.Terrain.GRASS)
	return world

func walk_journey(world: WorldState, journey: Dictionary) -> void:
	for id in journey.crew:
		var member := WorldLife.person(world,id)
		member.x = journey.route[0][0]; member.y = journey.route[0][1]
	for i in WorldTravel.MAX_PATH*2+5:
		if not world.journey_index.has(journey.id): break
		WorldTravel.step_journey(world,journey)

func test_trade() -> void:
	var world := land_pair()
	var a: Dictionary = world.towns[0]
	var b: Dictionary = world.towns[1]
	stock(world,b,"wood",0); stock(world,b,"stone",24)
	var offer := world.networks.offer(world,a,b)
	check(not offer.is_empty() and offer.kind=="wood" and offer.return_kind=="stone","trade follows a real timber deficit and pays with available stone")
	var wood_a: int = a.wood
	var stone_b: int = WorldCivilization.ensure(world,b).stock.stone
	var member: Dictionary = WorldEconomy.members(world,a)[0]
	check(WorldTravel.launch(world,a,b,[int(member.id)],"trade"),"need-based caravan launches")
	if world.journeys.is_empty(): return
	var journey: Dictionary = world.journeys[0]
	check(a.wood==wood_a-6 and journey.cargo==6 and WorldAudit.conserved(world),"cargo leaves the original store exactly once")
	check(copy(world)!=null,"barter cargo and terms roundtrip in transit")
	walk_journey(world,journey)
	check(b.wood==6 and WorldCivilization.ensure(world,a).stock.stone==3 and WorldCivilization.ensure(world,b).stock.stone==stone_b-3,"outbound and returning goods reach the actual stores")
	var link := world.networks.relation(a.id,b.id)
	check(not link.is_empty() and link.deliveries==1 and link.mode=="land" and link.route.size()>2,"completed land delivery retains a persistent route and trust")
	check(WorldAudit.conserved(world) and copy(world)!=null,"barter closes every resource balance and restores")
	stock(world,b,"food",0)
	offer = world.networks.offer(world,a,b)
	check(not offer.is_empty() and offer.aid and offer.kind=="food" and offer.return_amount==0,"starving neighbors receive unconditional food aid")
	check(WorldTravel.launch(world,a,b,[int(member.id)],"aid"),"aid uses a real carrier and paid provisions")
	if not world.journeys.is_empty(): walk_journey(world,world.journeys[0])
	check(b.food==6 and link.aid==1 and link.trust>=65 and WorldAudit.conserved(world),"aid reaches the hungry community and improves trust")
	var failed := {"home":a.id,"target":b.id}
	for i in 6: world.networks.failed(world,failed,"Условия обмена нарушены")
	check(not world.networks.permitted(a.id,b.id,world.ticks),"repeated failed deliveries can suspend ordinary exchange")
	stock(world,b,"food",120)
	check(world.networks.offer(world,a,b).is_empty(),"trade does not ignore an active dispute")
	world.ticks = int(link.blocked_until)
	check(world.networks.permitted(a.id,b.id,world.ticks),"trade suspension has a finite expiry")
	var header := WorldSaveHeaderJob.new(world,[],true)
	while not header.finished: header.unit()
	var captured := JSON.stringify(header.data.networks)
	link.trust = 1
	check(captured==JSON.stringify(header.data.networks),"background save owns independent relation data")
	check(copy(world)!=null,"relations survive time and updated trust")
	world.networks.forget_home(b.id)
	check(world.networks.links.is_empty() and world.networks.neighbors.get(a.id,[]).is_empty(),"abandonment removes obsolete links from both neighbor indices")

func test_colony() -> void:
	var world := WorldState.new()
	var a := home(world,Vector2i.ZERO)
	world.paint(Vector2i(40,0),30,WorldState.Terrain.GRASS)
	var grid := {WorldState.chunk_of(Vector2i.ZERO):[a]}
	var search := WorldColonySearchJob.new(world,a,grid)
	var units := 0
	while not search.finished: search.unit(); units += 1
	check(search.result!=WorldState.NO_CELL and units>32,"daughter settlement site search yields through a real reachable fertile area")
	var destination := {"id":-1,"name":"Новый очаг","x":search.result.x,"y":search.result.y}
	var group: Array = []
	for member in WorldEconomy.members(world,a).slice(0,3): group.append(int(member.id))
	check(WorldTravel.launch(world,a,destination,group,"colony"),"settlers carry food and construction timber over land")
	check(world.towns.size()==1 and a.wood==26,"new settlement appears after arrival and initial wood is not created")
	if world.journeys.is_empty(): return
	check(copy(world)!=null,"unfounded destination roundtrips mid-journey")
	walk_journey(world,world.journeys[0])
	check(world.towns.size()==2 and world.people.size()==6,"daughter settlement moves existing residents without population cloning")
	if world.towns.size()<2: return
	var child: Dictionary = world.towns[1]
	var state: Dictionary = world.networks.town_index.get(child.id,{})
	check(WorldEconomy.members(world,child).size()==3 and child.wood==6 and state.get("parent")==a.id,"actual cargo and founding origin reach the new community")
	check(WorldAudit.conserved(world) and copy(world)!=null,"settlement founding conserves inventories and original lives")

func test_projects() -> void:
	var world := WorldState.new()
	var a := home(world,Vector2i.ZERO)
	for y in range(-18,19):
		for x in [9,10]: world._set_terrain(Vector2i(x,y),WorldState.Terrain.WATER)
	var endpoint := Vector2i(11,0)
	check(not WorldEconomy.navigation(world,a).parents.has(endpoint),"water separates the two banks before a bridge")
	var span := [[9,0],[10,0],[11,0]]
	var bridge := WorldEconomy.add_building(world,a,"bridge",Vector2i(8,0),false,span)
	check(not world.walkable(Vector2i(9,0)),"unfinished bridge does not open navigation")
	bridge.ready = true; bridge.delivered = WorldEconomy.COST.bridge; bridge.work = WorldEconomy.WORK.bridge
	world.metrics.harvested_wood += WorldEconomy.COST.bridge; world.metrics.built_wood += WorldEconomy.COST.bridge
	for key in bridge.materials: bridge.materials[key] = WorldCivilization.EXTRA.bridge[key]; world.industry.produced[key] += bridge.materials[key]
	world.networks.completed(world,bridge)
	check(world.walkable(Vector2i(9,0)) and WorldEconomy.navigation(world,a).parents.has(endpoint),"completed bridge opens the actual walking graph")
	var member: Dictionary = world.people[0]
	var previous := Vector2i(member.x,member.y)
	member.x = 9; member.y = 0; world.track_person_move(member,previous)
	check(copy(world)!=null,"resident standing on a bridge restores before normal walkability validation")
	var baked := WorldLandscapeBakeJob.new(world,Vector2i.ZERO)
	baked.advance(0)
	check(baked.image.get_pixel(9*8+3,3).a>0,"bridge deck is part of the cached water overlay")
	world._set_terrain(endpoint,WorldState.Terrain.MOUNTAIN)
	check(not world.walkable(Vector2i(9,0)),"lost endpoint invalidates a bridge immediately")
	var repair := WorldTerrainRepairJob.new(world)
	while not repair.finished: repair.unit()
	check(world.walkable(Vector2i(member.x,member.y)) and not world.building_index.has(bridge.id),"bridge loss evacuates residents and removes the invalid structure")
	check(WorldAudit.conserved(world) and copy(world)!=null,"bridge destruction remains saveable and conserves materials")
	world = WorldState.new(); a = home(world,Vector2i.ZERO)
	for key in ["carpentry","stonework","ceramics","waterworks","mechanization","metallurgy"]: master(world,a,key)
	var farm := add_ready(world,a,"farm",Vector2i(4,-2))
	add_ready(world,a,"irrigation",Vector2i(-4,-2))
	farm.planted = true; world.drought_until = 100
	WorldEconomy.step_farm(world,farm)
	check(farm.growth==1,"irrigation permits actual crop growth during drought")
	add_ready(world,a,"mill",Vector2i(4,8))
	WorldEconomy.step_farm(world,farm)
	check(farm.growth==3,"mechanized mill accelerates real crop processing")
	var plaza := add_ready(world,a,"plaza",Vector2i(-4,8))
	member = world.people[0]; member.links = []
	check(WorldSocial.visit_target(world,member,a)==Vector2i(plaza.x+1,plaza.y+1),"plaza becomes a shared actual destination for social visits")
	var road := WorldEconomy.add_building(world,a,"roadworks",Vector2i(-10,2),true,[[1,0],[2,0]])
	world.metrics.harvested_wood += WorldEconomy.COST.roadworks; world.metrics.built_wood += WorldEconomy.COST.roadworks
	for key in road.materials: world.industry.produced[key] += road.materials[key]
	member.x = 0; member.y = 0; member.energy = 100
	WorldEconomy.move(world,member,Vector2i(2,0),a)
	check(member.energy==99.875,"paved road reduces fatigue only on actual road cells")
	check(copy(world)!=null and WorldAudit.conserved(world),"public works and materials survive save validation")

func test_project_construction() -> void:
	var world := WorldState.new()
	var a := home(world,Vector2i.ZERO)
	master(world,a,"carpentry")
	stock(world,a,"stone",12)
	for y in range(-18,19):
		for x in [9,10]: world._set_terrain(Vector2i(x,y),WorldState.Terrain.WATER)
	var planner := WorldPublicPlanJob.new(world,a)
	while not planner.finished: planner.unit()
	var project: Dictionary = {}
	for building in world.buildings:
		if building.kind=="bridge": project = building; break
	check(not project.is_empty() and not project.ready,"public planner schedules a useful unfinished bridge with a concrete span")
	if project.is_empty(): return
	var member: Dictionary = world.people[0]
	while project.delivered<int(WorldEconomy.COST.bridge):
		WorldEconomy.set_task(world,member,WorldEconomy.task("supply",Vector2i(a.x,a.y),project.id))
		for i in 100:
			WorldEconomy.execute(world,member,a)
			if member.task.is_empty(): break
	while not WorldCivilization.materials_ready(project):
		if not WorldCivilization.supply_assign(world,member,a,project): break
		for i in 100:
			WorldEconomy.execute(world,member,a)
			if member.task.is_empty(): break
	WorldEconomy.set_task(world,member,WorldEconomy.task("build",Vector2i(project.x,project.y),project.id))
	for i in 120:
		WorldEconomy.execute(world,member,a)
		if member.task.is_empty(): break
	check(project.ready and a.wood==20 and WorldCivilization.ensure(world,a).stock.stone==8,"normal carriers and builder spend the real wood, stone and labor")
	check(world.walkable(Vector2i(project.project_cells[0][0],project.project_cells[0][1])) and WorldAudit.conserved(world) and copy(world)!=null,"ordinary completion opens the bridge and preserves a valid resource balance")
	world.set_fire(Vector2i(project.x,project.y),12)
	member.x = project.project_cells[0][0]; member.y = project.project_cells[0][1]
	project.integrity = 2
	world.step()
	check(world.walkable(Vector2i(member.x,member.y)) and not WorldTravel.away(world,member.id),"bridge burned during a normal simulation tick evacuates its occupant")
	check(copy(world)!=null and WorldAudit.conserved(world),"mid-tick bridge destruction leaves a valid saved world")

func test_city() -> void:
	var world := WorldState.new()
	var a := home(world,Vector2i.ZERO,20)
	var apartment := add_ready(world,a,"apartment",Vector2i(-12,0))
	WorldLife.reconcile(world)
	var families := 0
	for family in world.households:
		if family.dwelling==apartment.id: families += 1
	check(families>1 and WorldLife.occupied_places(world,apartment.id)<=16,"one apartment building houses several existing households within capacity")
	check(WorldEconomy.housing(world,a)==28 and copy(world)!=null,"multi-family capacity is reflected in housing and save validation")
	for member in world.people: member.skills.build = 220
	for key in WorldSociety.TECH: master(world,a,key)
	for key in WorldCivilization.GOODS: stock(world,a,key,WorldCivilization.CAPACITY)
	stock(world,a,"wood",48)
	check(not world.networks.construction_ready(world,a,"tower"),"technology alone cannot build a skyscraper without running electricity")
	add_ready(world,a,"power",Vector2i(8,-12))
	var before: int = a.wood
	var monthly := WorldNetworksJob.new(world)
	while not monthly.finished: monthly.unit()
	check(a.wood==before-2 and world.networks.powered(world,a),"power generation consumes actual fuel once a month")
	check(world.networks.housing_kind(world,a)=="tower" and WorldDevelopment.construction_ready(world,a,"tower"),"experienced equipped community can choose highrise housing")
	stock(world,a,"metal",0)
	check(world.networks.housing_kind(world,a)=="townhouse","material shortage changes construction choice instead of free modern housing")
	check(copy(world)!=null and WorldAudit.conserved(world),"electricity and modern housing preserve finite resource accounting")
	var saved := world.to_dict()
	for mutation in ["missing","trust","project","span","duplicate","terms"]:
		var broken: Dictionary = saved.duplicate(true)
		match mutation:
			"missing": broken.erase("networks")
			"trust": broken.networks.towns[0].pressure = 101
			"project": broken.networks.towns[0].project = "imaginary"
			"span": broken.buildings.append({"kind":"bridge","id":broken.next_id,"x":0,"y":0,"ready":true,"project_cells":[[1e30,0],[2,0]]})
			"duplicate": broken.networks.towns.append(broken.networks.towns[0].duplicate(true))
			"terms":
				check(not WorldNetworks.valid_terms({"return_kind":"wood","return_amount":-1}),"negative exchange terms rejected")
				continue
		check(WorldState.from_dict(broken)==null,"invalid civic metadata rejected: "+mutation)

func test_maritime_and_failures() -> void:
	var world := WorldState.new()
	var a := home(world,Vector2i.ZERO)
	var b := home(world,Vector2i(10000,0),3)
	for key in ["preservation","carpentry","navigation","weaving","sailing"]: master(world,a,key)
	stock(world,b,"wood",0); stock(world,b,"stone",24)
	var vessel := add_ready(world,a,"sailboat",Vector2i(11,12))
	var coast := WorldMaritime.shore(world,b,Vector2i.ZERO); coast.town = b.id
	check(WorldMaritime.launch(world,a,vessel,coast,"trade"),"sea trade accepts the same deficit-based contract as a land caravan")
	if world.voyages.is_empty(): return
	var ship: Dictionary = world.voyages[0]
	check(ship.cargo_kind=="wood" and ship.return_kind=="stone" and copy(world)!=null,"sea contract and timber cargo are saved before sailing")
	WorldMaritime.arrive(world,ship)
	check(b.wood==6 and ship.cargo_kind=="stone" and ship.cargo==3,"sea exchange transfers the negotiated real cargo")
	WorldMaritime.land_crew(world,ship,a,Vector2i.ZERO); ship.phase = "unload"
	WorldMaritime.unload(world,ship)
	check(WorldCivilization.ensure(world,a).stock.stone==3 and WorldAudit.conserved(world),"returning ship unloads the actual payment without resource creation")
	var link := world.networks.relation(a.id,b.id)
	check(link.mode=="sea" and link.deliveries==1,"maritime arrival retains a real relation")
	vessel = add_ready(world,a,"sailboat",Vector2i(11,12))
	stock(world,b,"food",0)
	check(WorldMaritime.launch(world,a,vessel,coast,"aid"),"sea relief carries finite food without payment")
	if world.voyages.is_empty(): return
	ship = world.voyages[0]
	var origin := Vector2i(ship.origin[0],ship.origin[1])
	add_ready(world,a,"embankment",Vector2i(-12,-12))
	WorldWeather.start(world,"storm",origin,12,40)
	ship.phase = "outbound"; ship.progress = 0
	var integrity: int = ship.integrity
	WorldMaritime.step_ship(world,ship)
	check(ship.progress==1 and ship.integrity==integrity,"fortified shore protects an outbound vessel still near its home coast")
	ship.progress = ship.duration/2
	var current := WorldMaritime.position(ship)
	world.weather.active.clear(); WorldWeather.start(world,"storm",current,12,40)
	var progress: int = ship.progress
	WorldMaritime.step_ship(world,ship)
	check(ship.progress==progress and ship.integrity<integrity,"shore defenses do not protect a vessel far out at sea")
	world.weather.active.clear()
	WorldMaritime.arrive(world,ship)
	check(b.food==6 and link.aid==1,"food aid reaches the distant hungry shore")
	WorldMaritime.land_crew(world,ship,a,origin); ship.phase = "unload"; WorldMaritime.unload(world,ship)
	check(copy(world)!=null and WorldAudit.conserved(world),"sea aid and shore protection preserve a valid finite world")
	world = land_pair(); a = world.towns[0]; b = world.towns[1]
	stock(world,b,"wood",0); stock(world,b,"stone",24)
	var member: Dictionary = WorldEconomy.members(world,a)[0]
	check(WorldTravel.launch(world,a,b,[int(member.id)],"trade"),"interruption scenario launches with real cargo")
	if world.journeys.is_empty(): return
	var journey: Dictionary = world.journeys[0]
	WorldTravel.death(world,member.id)
	WorldTravel.step_journey(world,journey)
	WorldEconomy.set_task(world,member,{})
	check(world.journeys.is_empty() and WorldAudit.conserved(world) and copy(world)!=null,"last carrier loss accounts for provisions and wood without a stuck journey")

func test_sliced_continuation() -> void:
	var world := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))
	check(world!=null and WorldSociety.TECH.size()==18,"legacy world migrates to the extended technology catalog")
	if world==null: return
	for society in world.societies:
		for key in ["masonry","waterworks","mechanization","steam","electricity","urbanism","highrise"]:
			check(not society.tech[key].known and not society.tech[key].mastered,"migration grants no free modern technology: "+key)
	var resumed := copy(world)
	for i in WorldEconomy.DAY_TICKS*2:
		world.step()
		var job := WorldStepJob.new(resumed)
		while not job.finished: job.advance(2000)
	check(JSON.stringify(world.to_dict())==JSON.stringify(resumed.to_dict()),"full and budgeted monthly decisions continue identically after loading")
	check(WorldAudit.conserved(world) and copy(world)!=null,"autonomous monthly plans and trade remain conservative and saveable")

func test_directed_path() -> void:
	var world := WorldState.new()
	world.paint(Vector2i(64,0),64,WorldState.Terrain.GRASS)
	var path_job := WorldTravelPathJob.new(world,Vector2i.ZERO,Vector2i(120,0))
	path_job.advance(0)
	check(path_job.result.size()==121 and path_job.cursor<=130,"directed search reaches a distant town without flooding the whole work area")
	world._set_terrain(Vector2i(60,0),WorldState.Terrain.MOUNTAIN)
	path_job = WorldTravelPathJob.new(world,Vector2i.ZERO,Vector2i(120,0)); path_job.advance(0)
	check(path_job.result.size()==123,"directed path takes the shortest actual detour around new terrain")
	for row in path_job.result: check(world.walkable(Vector2i(row[0],row[1])),"directed route remains on walkable terrain")

func run() -> void:
	test_trade(); test_colony(); test_projects(); test_project_construction(); test_city(); test_maritime_and_failures(); test_sliced_continuation(); test_directed_path()
	print("Living civilizations: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
