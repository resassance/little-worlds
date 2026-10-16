extends "res://tests/living_civilizations_test.gd"

func plan_work(world: WorldState, settlement: Dictionary) -> Dictionary:
	WorldEconomy.navigation(world,settlement)
	for month_index in 16:
		world.ticks = (month_index+1)*WorldEconomy.DAY_TICKS
		var job := WorldLandworksJob.new(world)
		var count := 0
		while not job.finished:
			job.unit(); count += 1
		check(count<=WorldLandworks.SEARCH_LIMIT+4,"land work search has a fixed local unit budget")
		if not settlement.landworks.project.is_empty(): return settlement.landworks.project
	return {}

func start_work(world: WorldState, settlement: Dictionary, mode: String, cell: Vector2i, stand: Vector2i) -> Dictionary:
	var state := WorldLandworks.state_for(world,settlement)
	state.serial += 1
	state.project = {"mode":mode,"x":cell.x,"y":cell.y,"stand_x":stand.x,"stand_y":stand.y,"work":0,"ready":false}
	var member: Dictionary = WorldEconomy.members(world,settlement)[0]
	var previous := Vector2i(member.x,member.y)
	member.x = settlement.x; member.y = settlement.y; member.cargo = 0; member.cargo_kind = ""
	world.track_person_move(member,previous)
	WorldEconomy.set_task(world,member,{})
	check(WorldLandworks.assign(world,member,settlement),"available specialist accepts "+mode)
	return member

func finish_work(world: WorldState, settlement: Dictionary, member: Dictionary) -> void:
	for i in 200:
		if member.task.is_empty(): break
		world.ticks += 1
		WorldEconomy.execute(world,member,settlement)
	check(member.task.is_empty() and settlement.landworks.project.get("ready",false),"completed labor waits for terrain application")
	check(WorldAudit.conserved(world) and copy(world)!=null,"paid work and terrain pending application roundtrip")
	var job := WorldLandworksJob.new(world)
	world.stepping = true
	while not job.finished: job.unit()
	world.stepping = false
	while not world.networks.navigation_queue.is_empty():
		var destination := WorldEconomy.town(world,world.networks.navigation_queue.pop_front())
		if not destination.is_empty():
			var navigation_job := WorldNavigationJob.new(world,destination)
			while not navigation_job.finished: navigation_job.unit()
	check(WorldAudit.conserved(world) and copy(world)!=null,"finished terrain preserves stock balances and valid saves")

func test_forest() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	master(world,settlement,"carpentry")
	stock(world,settlement,"wood",0)
	var trees: Array = WorldEconomy.navigation(world,settlement).wood.duplicate()
	for cell in trees: world._set_terrain(cell,WorldState.Terrain.GRASS)
	var project := plan_work(world,settlement)
	check(not project.is_empty() and project.mode=="forest","timber scarcity plans a real forest planting site")
	if project.is_empty(): return
	var cell := Vector2i(project.x,project.y)
	var member: Dictionary = WorldEconomy.members(world,settlement)[0]
	check(WorldLandworks.assign(world,member,settlement),"an adult takes the planned planting")
	var another: Dictionary = WorldEconomy.members(world,settlement)[1]
	check(not WorldLandworks.assign(world,another,settlement),"only one resident owns the same town project")
	var original_food: int = settlement.food
	WorldEconomy.execute(world,member,settlement)
	check(member.cargo==2 and member.cargo_kind=="food" and settlement.food==original_food-2 and world.terrain_at(cell)==WorldState.Terrain.GRASS,"seeds leave storage and terrain is unchanged before arrival")
	check(WorldAudit.conserved(world) and copy(world)!=null,"terraforming cargo survives reload without creating resources")
	for i in 200:
		if project.work>0: break
		world.ticks += 1; WorldEconomy.execute(world,member,settlement)
	var saved := copy(world)
	check(saved!=null and saved.towns[0].landworks.project.work==project.work and project.work>0,"partial work is persistent")
	WorldEconomy.set_task(world,member,{})
	check(member.cargo==2 and WorldAudit.conserved(world),"interruption retains the real carried seeds")
	WorldEconomy.assign(world,member,settlement)
	for i in 100:
		if member.task.is_empty(): break
		WorldEconomy.execute(world,member,settlement)
	check(member.cargo==0 and settlement.food==original_food,"interrupted supplies can be returned intact")
	check(WorldLandworks.assign(world,member,settlement),"unfinished work can be resumed")
	finish_work(world,settlement,member)
	check(world.terrain_at(cell)==WorldState.Terrain.FOREST and world.wood_at(cell)==12 and settlement.landworks.completed.forest==1,"resident planting grows harvestable forest")
	check(world.metrics.processed_food==2 and settlement.food==original_food-2,"only completed planting consumes its seed material once")
	check(WorldEconomy.navigation(world,settlement).wood.has(cell),"new forest enters the actual resource navigation index")

func test_earthworks() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	for key in ["rotation","stonework","masonry","waterworks"]: master(world,settlement,key)
	stock(world,settlement,"tools",5); stock(world,settlement,"stone",30)
	var cell := Vector2i(6,0)
	world._set_terrain(cell,WorldState.Terrain.SAND)
	world._set_terrain(cell+Vector2i.RIGHT,WorldState.Terrain.WATER)
	var member := start_work(world,settlement,"cultivate",cell,cell)
	finish_work(world,settlement,member)
	check(world.terrain_at(cell)==WorldState.Terrain.GRASS and WorldEconomy.navigation(world,settlement).food.has(cell),"soil cultivation makes real fertile ground near water")
	cell = Vector2i(6,8)
	world._set_terrain(cell,WorldState.Terrain.WATER)
	member = start_work(world,settlement,"reclaim",cell,cell+Vector2i.LEFT)
	var stone: int = WorldCivilization.ensure(world,settlement).stock.stone
	var sea_revision: int = world.sea_revision
	finish_work(world,settlement,member)
	check(world.terrain_at(cell)==WorldState.Terrain.SAND and world.walkable(cell) and WorldCivilization.ensure(world,settlement).stock.stone==stone-6,"earthworks consume delivered stone and create walkable land")
	check(world.sea_revision>sea_revision and WorldEconomy.navigation(world,settlement).parents.has(cell),"new shoreline invalidates sea routes and joins local walking routes")
	for y in range(-18,19): world._set_terrain(Vector2i(10,y),WorldState.Terrain.MOUNTAIN)
	cell = Vector2i(10,0)
	check(not WorldEconomy.navigation(world,settlement).parents.has(Vector2i(11,0)),"mountain barrier blocks the far valley")
	member = start_work(world,settlement,"pass",cell,Vector2i(9,0))
	var tools: int = WorldCivilization.ensure(world,settlement).stock.tools
	finish_work(world,settlement,member)
	check(world.terrain_at(cell)==WorldState.Terrain.SAND and WorldEconomy.navigation(world,settlement).parents.has(Vector2i(11,0)),"completed pass opens a formerly inaccessible valley")
	check(WorldCivilization.ensure(world,settlement).stock.tools==tools-1 and world.industry.consumed.tools==1,"pass construction consumes carried tools exactly once")

func test_safety() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	master(world,settlement,"carpentry")
	var cell := Vector2i(-6,0)
	var member := start_work(world,settlement,"forest",cell,cell)
	WorldEconomy.execute(world,member,settlement)
	world._set_terrain(cell,WorldState.Terrain.SAND)
	WorldEconomy.execute(world,member,settlement)
	check(member.task.is_empty() and settlement.landworks.project.is_empty() and member.cargo==2 and WorldAudit.conserved(world),"player changes cancel obsolete work without losing carried resources")
	check(copy(world)!=null,"cancelled work remains saveable")
	var nav := WorldEconomy.navigation(world,settlement)
	var occupied := Vector2i(settlement.x,settlement.y)
	check(not WorldLandworks.suitable(world,settlement,"forest",occupied,occupied,nav),"land workers protect buildings")
	world._set_terrain(cell,WorldState.Terrain.GRASS)
	world.set_fire(cell,12)
	check(not WorldLandworks.suitable(world,settlement,"forest",cell,cell,nav),"residents do not terraform burning terrain")
	world.fires.clear(); world.fire_regions.clear()
	WorldClimate.paint(world,cell,0,5)
	check(not WorldLandworks.suitable(world,settlement,"forest",cell,cell,nav),"ordinary forest planting respects polar climate")
	world = WorldState.new(); settlement = home(world,Vector2i.ZERO)
	for key in ["waterworks","masonry"]: master(world,settlement,key)
	cell = Vector2i(6,0); world._set_terrain(cell,WorldState.Terrain.WATER)
	nav = WorldEconomy.navigation(world,settlement)
	world.voyages.append({})
	check(not WorldLandworks.suitable(world,settlement,"reclaim",cell,Vector2i(5,0),nav),"earthworks cannot disrupt an active voyage")
	world.voyages.clear()
	for mutation in ["work","mode","range","counter"]:
		var state := WorldLandworks.state_for(world,settlement)
		state.project = {"mode":"reclaim","x":6,"y":0,"stand_x":5,"stand_y":0,"work":0,"ready":false}
		var data := JSON.parse_string(JSON.stringify(world.to_dict())) as Dictionary
		var damaged: Dictionary = data.towns[0].landworks
		match mutation:
			"work": damaged.project.work = 10000
			"mode": damaged.project.mode = "invalid"
			"range": damaged.project.x = 100000
			"counter": damaged.completed.forest = -1
		check(WorldState.from_dict(data)==null,"malformed land project rejected: "+mutation)
	var legacy := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/living-civilizations-world.json")))
	check(legacy!=null and legacy.people.size()==102,"existing v13 cities migrate without replacing their world")

func test_expansion() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO,12)
	world.paint(Vector2i(40,0),30,WorldState.Terrain.GRASS)
	stock(world,settlement,"food",168)
	var member: Dictionary = world.people[0]
	check(WorldExploration.assign(world,member,settlement) and member.task.reason=="territory","healthy growing towns scout land before a crisis")
	check(copy(world)!=null,"territory exploration and claims survive a save")
	for i in 160:
		if member.task.is_empty(): break
		WorldEconomy.execute(world,member,settlement)
	check(settlement.survey.pending_radius==32,"knowledge expands only after the scout returns")
	WorldExploration.prepare(world,settlement)
	var navigation_job := WorldNavigationJob.new(world,settlement)
	while not navigation_job.finished: navigation_job.unit()
	WorldExploration.report(world,settlement)
	check(WorldLandworks.expanding(world,settlement),"abundant food, timber, residents and surveyed land support expansion")
	world.ticks = WorldEconomy.DAY_TICKS
	var job := WorldTravelDailyJob.new(world)
	var units := 0
	while not job.finished and units<20000: job.unit(); units += 1
	check(not world.journeys.is_empty() and world.journeys[0].purpose=="colony","prosperous settlement sends a real colony without migration pressure")
	check(units>100 and units<12000,"colony surveying advances through bounded small search units")
	if world.journeys.is_empty(): return
	check(WorldAudit.conserved(world) and copy(world)!=null,"new colony begins with conserved supplies and existing residents")
	walk_journey(world,world.journeys[0])
	check(world.towns.size()==2 and WorldEconomy.members(world,settlement).size()>=4 and world.people.size()==12,"settlers occupy new territory while leaving the parent community alive")
	check(world.networks.state_for(world,settlement).next_migration>=WorldLife.YEAR,"successful settlement has an annual expansion cooldown")
	check(WorldAudit.conserved(world) and copy(world)!=null,"autonomous expansion conserves food, wood and population")

func compact_home(world: WorldState, terrain: int, population: int) -> Dictionary:
	world.paint(Vector2i.ZERO,8,terrain)
	var settlement := {"id":world.next_id,"name":"Малый остров","x":0,"y":0,"food":120,"wood":0,"level":1}
	world.next_id += 1; world.towns.append(settlement); world.metrics.spawn_food += 120
	add_ready(world,settlement,"camp",Vector2i.ZERO)
	add_ready(world,settlement,"store",Vector2i(-4,-4))
	for i in population:
		world.add_person(Vector2i(i%3,i/3),false)
		var member: Dictionary = world.people.back()
		member.home = settlement.id; member.birth_tick = -25*WorldLife.YEAR; member.sex = "male"
		for skill in WorldSocial.SKILLS: member.skills[skill] = 120
	WorldLife.reconcile(world)
	return settlement

func test_local_planning() -> void:
	var world := WorldState.new()
	var settlement := compact_home(world,WorldState.Terrain.SAND,6)
	master(world,settlement,"rotation")
	world._set_terrain(Vector2i(4,0),WorldState.Terrain.GRASS)
	world._set_terrain(Vector2i(6,0),WorldState.Terrain.WATER)
	var project := plan_work(world,settlement)
	check(not project.is_empty() and project.mode=="cultivate","food-poor sandy land generates its own cultivation project")
	check(copy(world)!=null,"automatically selected soil project is saveable")
	world = WorldState.new(); settlement = compact_home(world,WorldState.Terrain.GRASS,20)
	for key in ["waterworks","masonry"]: master(world,settlement,key)
	stock(world,settlement,"food",168); stock(world,settlement,"stone",30)
	project = plan_work(world,settlement)
	check(not project.is_empty() and project.mode=="reclaim","crowded island generates a shoreline expansion project")
	if not project.is_empty():
		var cell := Vector2i(project.x,project.y)
		check(world.terrain_at(cell)==WorldState.Terrain.WATER,"shoreline is not changed by planning alone")
		var member: Dictionary = world.people[0]
		check(WorldLandworks.assign(world,member,settlement),"resident accepts automatically planned shore work")
		finish_work(world,settlement,member)
		check(world.walkable(cell),"residents expand the actual small island")
	world = WorldState.new(); settlement = home(world,Vector2i.ZERO)
	master(world,settlement,"carpentry"); stock(world,settlement,"wood",0)
	var trees: Array = WorldEconomy.navigation(world,settlement).wood.duplicate()
	for cell in trees: world._set_terrain(cell,WorldState.Terrain.GRASS)
	for i in 220: world.step()
	check(settlement.get("landworks",{}).get("completed",{}).get("forest",0)>0,"normal economy plans and performs planting without direct assignment")
	check(WorldAudit.conserved(world) and copy(world)!=null,"autonomous planting stays conservative through ordinary simulation")

func test_locality() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	world.ticks = WorldEconomy.DAY_TICKS
	WorldEconomy.navigation(world,settlement)
	var job := WorldLandworksJob.new(world)
	var before := 0
	while not job.finished: job.unit(); before += 1
	for i in 160: world._set_terrain(Vector2i(100000+i*64,100000),WorldState.Terrain.GRASS)
	world.regions.trim(world)
	var cold := world.regions.cold.duplicate(true)
	var loaded := world.chunks.size()
	job = WorldLandworksJob.new(world)
	var after := 0
	while not job.finished: job.unit(); after += 1
	check(after==before,"empty distant regions do not add land development work")
	check(world.regions.cold==cold and world.chunks.size()==loaded,"land development does not wake or load distant empty regions")
	check(settlement.landworks.project.is_empty(),"no pointless projects are scheduled without needs and methods")

func test_first_seed() -> void:
	var existed := FileAccess.file_exists(GamePreferences.PATH)
	var original := FileAccess.get_file_as_string(GamePreferences.PATH) if existed else ""
	var a := GamePreferences.new()
	var seed_value := a.initial_seed()
	check(seed_value>0 and seed_value<=2147483647 and a.initial_seed()==seed_value,"first seed is random within the editable range and stable within a session")
	var b := GamePreferences.new(); b.load_preferences()
	check(b.first_world_seed==seed_value and b.initial_seed()==seed_value,"first island seed persists before the initial world autosave")
	var seeds := {}
	for i in 12:
		var fresh := GamePreferences.new()
		seeds[fresh.initial_seed()] = true
	check(seeds.size()>1,"different new players receive different initial seeds")
	var x := WorldState.new(); x.generate(seed_value)
	var y := WorldState.new(); y.generate(seed_value)
	check(x.tiles==y.tiles and x.rng.state==y.rng.state,"an explicit seed still reproduces the same terrain and simulation RNG")
	if existed:
		var file := FileAccess.open(GamePreferences.PATH,FileAccess.WRITE)
		file.store_string(original); file.close()
	else: DirAccess.remove_absolute(GamePreferences.PATH)

func test_territory_continuation() -> void:
	var original := WorldState.new()
	var settlement := home(original,Vector2i.ZERO)
	master(original,settlement,"carpentry")
	var member := start_work(original,settlement,"forest",Vector2i(-6,0),Vector2i(-6,0))
	WorldEconomy.execute(original,member,settlement)
	var sliced := copy(original)
	check(sliced!=null,"active landworks fixture restores")
	if sliced==null: return
	for i in 90:
		original.step()
		var job := WorldStepJob.new(sliced)
		while not job.finished: job.advance(100)
	check(JSON.stringify(original.to_dict())==JSON.stringify(sliced.to_dict()),"landworks produce identical continuation with full and sliced simulation")
	check(WorldAudit.conserved(original),"landworks remain conservative inside full simulation")
	check(original.terrain_at(Vector2i(-6,0))==WorldState.Terrain.FOREST and settlement.landworks.completed.forest==1,"normal simulation finishes actual resident work")

func run() -> void:
	test_forest(); test_earthworks(); test_safety(); test_expansion(); test_local_planning(); test_locality(); test_first_seed(); test_territory_continuation()
	print("Territory: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
