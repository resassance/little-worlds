extends "res://tests/living_civilizations_test.gd"

func complete_animal_work(world: WorldState, settlement: Dictionary, member: Dictionary) -> void:
	for i in 150:
		if member.task.is_empty(): break
		world.ticks += 1; WorldEconomy.execute(world,member,settlement)
	check(member.task.is_empty(),"animal work finishes after walking and labor")
	check(WorldAudit.conserved(world) and copy(world)!=null,"animal work and cargo preserve balances and saves")

func return_load(world: WorldState, settlement: Dictionary, member: Dictionary) -> void:
	WorldEconomy.assign(world,member,settlement)
	for i in 120:
		if member.task.is_empty(): break
		WorldEconomy.execute(world,member,settlement)
	check(member.cargo==0 and WorldAudit.conserved(world),"real animal products are delivered to storage")

func test_animals() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	var herd := world.fauna.add(world,"sheep",Vector2i(-6,0),6)
	var member: Dictionary = world.people[0]
	check(world.fauna.assign(world,member,settlement) and member.task.action=="tame","experienced forager can begin taming without a forest technology gate")
	var initial: int = settlement.food
	WorldEconomy.execute(world,member,settlement)
	check(member.cargo==2 and settlement.food==initial-2 and herd.home==-1,"taming food leaves storage before animals change ownership")
	check(copy(world)!=null and WorldAudit.conserved(world),"taming supplies survive save and load")
	complete_animal_work(world,settlement,member)
	check(herd.home==settlement.id and world.fauna.owned(settlement)==6 and world.metrics.processed_food==2,"taming transfers the existing herd and consumes real food once")
	check(member.skills.farm>120,"animal care gives real farm practice")
	world.ticks = int(herd.milk_tick)
	check(world.fauna.assign(world,member,settlement,true) and member.task.action=="milk","owned animals become a physical food job")
	complete_animal_work(world,settlement,member)
	check(member.cargo==1 and member.cargo_kind=="food","basic herding yields carried food")
	return_load(world,settlement,member)
	check(settlement.food==initial-1,"animal food reaches the same original town")
	master(world,settlement,"husbandry")
	stock(world,settlement,"food",168)
	check(world.fauna.assign(world,member,settlement) and member.task.action=="shear","husbandry opens actual sheep shearing")
	complete_animal_work(world,settlement,member)
	check(member.cargo_kind=="wool" and member.cargo==2 and world.industry.produced.wool==2,"shearing produces real wool cargo")
	return_load(world,settlement,member)
	check(WorldCivilization.ensure(world,settlement).stock.wool==2,"wool enters the industrial store")
	check(world.networks.stock_goal(world,settlement,"wool")==0,"wool is not imported into a town without weaving equipment")
	add_ready(world,settlement,"loom",Vector2i(-12,0)); master(world,settlement,"weaving")
	check(WorldCivilization.assign(world,member,settlement) and member.task.resource=="cloth" and member.task.fiber=="wool","weavers choose available wool as their actual input")
	for i in 150:
		if member.task.is_empty(): break
		world.ticks += 1; WorldEconomy.execute(world,member,settlement)
	check(member.cargo_kind=="cloth" and member.cargo==2 and WorldCivilization.ensure(world,settlement).stock.wool==1 and world.industry.consumed.wool==1,"wool is consumed once to make carried fabric")
	check(WorldAudit.conserved(world) and copy(world)!=null,"wool processing closes all material ledgers")
	return_load(world,settlement,member)
	var old_population := world.people.size()
	WorldEconomy.plan(world,settlement)
	check(WorldDevelopment.construction_ready(world,settlement,"pasture") and world.people.size()==old_population,"pasture requires knowledge and actual livestock")

func test_hunting_and_cancel() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	stock(world,settlement,"food",0)
	var herd := world.fauna.add(world,"deer",Vector2i(-6,0),3)
	var member: Dictionary = world.people[0]
	check(world.fauna.assign(world,member,settlement,true) and member.task.action=="hunt","hungry community can hunt a real wild herd")
	complete_animal_work(world,settlement,member)
	check(herd.count==2 and member.cargo==3 and world.metrics.harvested_food==3,"hunting reduces animals rather than generating endless meat")
	return_load(world,settlement,member)
	stock(world,settlement,"food",120)
	herd = world.fauna.add(world,"goat",Vector2i(-6,1),3)
	member.energy = 100
	check(world.fauna.assign(world,member,settlement),"taming begins on a second wild herd")
	WorldEconomy.execute(world,member,settlement)
	WorldEconomy.set_task(world,member,{})
	check(member.cargo==2 and herd.home==-1 and WorldAudit.conserved(world),"interruption keeps taming supplies with their carrier")
	return_load(world,settlement,member)
	check(copy(world)!=null,"interrupted animal work restores")

func test_ecology() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	var herd := world.fauna.add(world,"goat",Vector2i(-6,0),3,settlement.id)
	for month_index in 3:
		for direction in [Vector2i.ZERO]+WorldState.DIRECTIONS: world._set_food(Vector2i(herd.x,herd.y)+direction,0)
		world.ticks = (month_index+1)*WorldEconomy.DAY_TICKS
		var job := WorldFaunaJob.new(world)
		while not job.finished: job.unit()
	check(herd.count==2 and world.fauna.owned(settlement)==2,"forage shortage causes actual losses and updates ownership counts: %d/%d" % [herd.count,world.fauna.owned(settlement)])
	var cell := Vector2i(herd.x,herd.y)
	world.set_fire(cell,12)
	world.ticks += 1
	var job := WorldFaunaJob.new(world)
	while not job.finished: job.unit()
	check(Vector2i(herd.x,herd.y)!=cell and not world.fires.has(Vector2i(herd.x,herd.y)),"herd responds to fire between monthly grazing updates")
	world.erase_fire(cell)
	cell = Vector2i(herd.x,herd.y)
	world._set_terrain(cell,WorldState.Terrain.WATER)
	job = WorldFaunaJob.new(world)
	while not job.finished: job.unit()
	check(WorldFauna.safe(world,Vector2i(herd.x,herd.y)),"terrain edits relocate a herd to nearby real ground")
	check(copy(world)!=null and WorldAudit.conserved(world),"ecological changes remain valid and conservative")

func test_brush_repair() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	var herd := world.fauna.add(world,"goat",Vector2i(-6,0),3)
	var member: Dictionary = world.people[0]
	check(world.fauna.assign(world,member,settlement),"terrain edit fixture starts a real animal task")
	WorldEconomy.execute(world,member,settlement)
	world.paint(Vector2i(-6,0),2,WorldState.Terrain.WATER)
	check(not world.fauna.index.has(herd.id) and member.task.is_empty() and member.cargo==2,"terrain repair removes a drowned herd and cancels its task without consuming the load")
	check(copy(world)!=null and WorldAudit.conserved(world),"world can save immediately after editing an animal worksite")
	world = WorldState.new(); settlement = home(world,Vector2i.ZERO)
	herd = world.fauna.add(world,"sheep",Vector2i(-6,0),3,settlement.id)
	world.paint(Vector2i.ZERO,0,WorldState.Terrain.WATER)
	check(herd.home==-1,"animals return to the wild when their settlement is destroyed")
	check(copy(world)!=null and WorldAudit.conserved(world),"settlement loss preserves a valid animal and material state")

func test_pasture_births() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	var herd := world.fauna.add(world,"goat",Vector2i(-9,0),6,settlement.id)
	world.ticks = WorldEconomy.DAY_TICKS; herd.birth_tick = world.ticks
	var job := WorldFaunaJob.new(world)
	while not job.finished: job.unit()
	check(herd.count==6,"an unprepared camp does not support an unlimited flock")
	add_ready(world,settlement,"pasture",Vector2i(-11,-1))
	world.ticks += WorldEconomy.DAY_TICKS; herd.birth_tick = world.ticks
	job = WorldFaunaJob.new(world)
	while not job.finished: job.unit()
	check(herd.count==7 and world.fauna.owned(settlement)==7,"a pasture and sufficient real forage permit herd growth")
	check(WorldAudit.conserved(world) and copy(world)!=null,"pasture growth and grazed terrain remain saveable")

func test_discovery_and_limits() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	WorldEconomy.navigation(world,settlement)
	for month_index in 12:
		world.ticks = (month_index+1)*WorldEconomy.DAY_TICKS
		var job := WorldFaunaJob.new(world)
		var units := 0
		while not job.finished: job.unit(); units += 1
		check(units<60,"fauna discovery has a small local monthly unit count")
	check(not world.fauna.herds.is_empty() and world.fauna.herds.size()<=4,"real settled outskirts discover a bounded set of wild herds: %d" % world.fauna.herds.size())
	var count := world.fauna.herds.size()
	for i in 160: world._set_terrain(Vector2i(100000+i*64,100000),WorldState.Terrain.GRASS)
	world.regions.trim(world)
	var cold := world.regions.cold.duplicate(true)
	world.ticks += WorldEconomy.DAY_TICKS
	var job := WorldFaunaJob.new(world)
	while not job.finished: job.unit()
	check(world.fauna.herds.size()<=4 and world.regions.cold==cold,"distant empty land neither spawns extra animals nor wakes cold regions")
	var dormant := world.fauna.add(world,"sheep",Vector2i(100000,100000),3)
	check(not dormant.is_empty(),"fixture has a distant real group")
	var before := JSON.stringify(dormant)
	world.ticks += WorldEconomy.DAY_TICKS
	job = WorldFaunaJob.new(world)
	while not job.finished: job.unit()
	check(JSON.stringify(dormant)==before,"animals outside active settlements stay dormant")
	check(copy(world)!=null,"active and dormant groups restore with their independent random stream")
	var empty := WorldState.new()
	empty.paint(Vector2i.ZERO,8,WorldState.Terrain.GRASS)
	for i in WorldFauna.LIMIT: empty.fauna.add(empty,"goat",Vector2i(2,0),3)
	check(empty.fauna.add(empty,"goat",Vector2i(2,0),3).is_empty() and empty.fauna.herds.size()==WorldFauna.LIMIT,"global herd limit prevents unbounded group growth")

func test_cultures() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	for i in 5:
		WorldCulture.record(world,settlement,"agrarian",32)
		world.ticks += WorldEconomy.DAY_TICKS; WorldCulture.monthly(world,settlement)
	check(settlement.culture.focus=="agrarian" and settlement.culture.strength>=40,"repeated real work gradually establishes a tradition")
	var member: Dictionary = world.people[0]
	member.traits.diligence = 0
	var farm := add_ready(world,settlement,"farm",Vector2i(-12,0))
	WorldEconomy.set_task(world,member,WorldEconomy.task("harvest",Vector2i(farm.x,farm.y),farm.id))
	world.ticks += posmod(-world.ticks-int(member.id),6)
	var xp: int = member.skills.farm
	WorldSocial.practice(world,member,"farm")
	check(member.skills.farm==xp+2,"established tradition improves practice in its actual craft")
	WorldEconomy.set_task(world,member,{})
	check(copy(world)!=null,"culture memory persists without inventing technologies")
	for i in 6:
		WorldCulture.record(world,settlement,"maritime",48)
		world.ticks = (world.ticks/WorldEconomy.DAY_TICKS+1)*WorldEconomy.DAY_TICKS; WorldCulture.monthly(world,settlement)
	check(settlement.culture.focus=="maritime","sustained economic change can replace an earlier tradition")
	var child := home(world,Vector2i(56,0))
	world.networks.ancestry(world,child,settlement)
	check(child.culture.focus=="maritime" and child.culture.strength==int(settlement.culture.strength)/2,"colonists inherit a weaker tradition that can adapt")
	check(WorldAudit.conserved(world) and copy(world)!=null,"traditions and founding origins keep existing resource balances")
	for i in 30:
		world.ticks += WorldEconomy.DAY_TICKS; WorldCulture.monthly(world,settlement)
	check(settlement.culture.strength==0,"unused traditions lose their learning benefit")

func test_migration_and_continuation() -> void:
	for fixture in ["advanced-46-world.json","living-civilizations-world.json","territory-world.json"]:
		var old := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+fixture)))
		check(old!=null,"old world migrates: "+fixture)
		if old!=null: check(WorldCivilization.ensure(old,old.towns[0]).stock.wool==0 and WorldSociety.get_society(old,old.towns[0].id).tech.has("husbandry"),"migration adds empty wool stock and unlearned husbandry")
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO)
	world.fauna.add(world,"sheep",Vector2i(-6,0),6)
	world.fauna.assign(world,world.people[0],settlement)
	WorldEconomy.execute(world,world.people[0],settlement)
	var sliced := copy(world)
	check(sliced!=null,"active taming fixture restores")
	if sliced==null: return
	for i in 140:
		world.step()
		var job := WorldStepJob.new(sliced)
		while not job.finished: job.advance(100)
	check(JSON.stringify(world.to_dict())==JSON.stringify(sliced.to_dict()),"fauna and traditions continue identically with full and sliced simulation")
	check(WorldAudit.conserved(world),"full simulation preserves every material including wool")
	check(world.fauna.owned(settlement)>0,"ordinary simulation finishes taming and maintains domestic animals")
	var header := WorldSaveHeaderJob.new(world,[],true)
	while not header.finished: header.unit()
	var captured := JSON.stringify(header.data.fauna)
	world.fauna.herds[0].count += 1
	check(captured==JSON.stringify(header.data.fauna),"background save owns independent herd data")
	var data: Dictionary = sliced.to_dict()
	data.fauna.herds[0].count = 1000
	check(WorldState.from_dict(data)==null,"malformed herd population is rejected")
	data = sliced.to_dict(); data.towns[0].culture.strength = 1000
	check(WorldState.from_dict(data)==null,"malformed tradition strength is rejected")

func run() -> void:
	test_animals(); test_hunting_and_cancel(); test_ecology(); test_brush_repair(); test_pasture_births(); test_discovery_and_limits(); test_cultures(); test_migration_and_continuation()
	print("Pastures and traditions: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
