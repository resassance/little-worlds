extends SceneTree
var checks := 0
var failures := 0
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func home(w: WorldState, center: Vector2i, population: int = 6) -> Dictionary:
	w.paint(center, 18, WorldState.Terrain.GRASS)
	w.paint(center + Vector2i(9, 0), 3, WorldState.Terrain.FOREST)
	var h := {"id": w.next_id, "name": "Берег %d" % w.next_id, "x": center.x, "y": center.y, "food": 120, "wood": 32, "level": 3}
	w.next_id += 1
	w.towns.append(h)
	w.metrics.spawn_food += 120
	w.metrics.harvested_wood += 32
	for spec in [["camp", Vector2i.ZERO], ["store", Vector2i(-7,-7)], ["house", Vector2i(4,4)], ["house",Vector2i(-7,4)], ["workshop",Vector2i(4,-7)], ["archive",Vector2i(-2,-7)], ["dock",Vector2i(0,16)]]:
		add_ready(w, h, spec[0], center + spec[1])
	for i in population:
		w.add_person(center + Vector2i(i % 3, i / 3), false)
		var p: Dictionary = w.people.back()
		p.home = h.id
		p.birth_tick = -25 * WorldLife.YEAR
		p.sex = "male"
		for skill in WorldSocial.SKILLS: p.skills[skill] = 120
	WorldLife.reconcile(w)
	return h

func add_ready(w: WorldState, h: Dictionary, kind: String, cell: Vector2i) -> Dictionary:
	var b := WorldEconomy.add_building(w,h,kind,cell,true)
	w.metrics.harvested_wood += WorldEconomy.COST[kind]
	w.metrics.built_wood += WorldEconomy.COST[kind]
	for key in b.materials: w.industry.produced[key] += b.materials[key]
	return b

func master(w: WorldState, h: Dictionary, key: String) -> void:
	var s := WorldSociety.get_society(w,h.id)
	s.tech[key].known = true
	s.tech[key].mastered = true
	s.tech[key].progress = WorldSociety.TECH[key].work
	s.tech[key].discovered_tick = w.ticks
	WorldSociety.invalidate(w)

func copy(w: WorldState) -> WorldState:
	return WorldState.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))

func run() -> void:
	var w := WorldState.new()
	var h := home(w,Vector2i.ZERO)
	master(w,h,"carpentry")
	w.paint(Vector2i(7,0),0,WorldState.Terrain.MOUNTAIN)
	var p: Dictionary = w.people[0]
	check(WorldCivilization.assign(w,p,h) and p.task.kind == "quarry", "local mountain creates a physical quarry job")
	WorldEconomy.execute(w,p,h)
	check(p.cargo == 0 and p.x != p.task.x, "mining requires walking before extraction")
	for i in 80:
		if p.task.is_empty(): break
		WorldEconomy.execute(w,p,h)
	check(p.cargo == 3 and w.mineral_deposits[Vector2i(7,0)] == 33, "finite mountain material is carried by miner")
	WorldEconomy.assign(w,p,h)
	for i in 80:
		if p.task.is_empty(): break
		WorldEconomy.execute(w,p,h)
	check(WorldCivilization.ensure(w,h).stock.stone == 3 and WorldAudit.conserved(w), "stone arrives at camp and all resource balances close")
	var kiln := WorldEconomy.add_building(w,h,"kiln",Vector2i(-12,0))
	var stock: Dictionary = WorldCivilization.ensure(w,h).stock
	stock.stone += 3; w.industry.produced.stone += 3
	p.x=0; p.y=0
	check(WorldCivilization.supply_assign(w,p,h,kiln), "new buildings require actual additional materials")
	WorldEconomy.execute(w,p,h)
	check(p.cargo == 4 and kiln.materials.stone == 0 and stock.stone == 2, "stone leaves stock and enters carried cargo")
	check(copy(w) != null, "material delivery roundtrips")
	for i in 80:
		if p.task.is_empty(): break
		WorldEconomy.execute(w,p,h)
	check(kiln.materials.stone == 4 and WorldCivilization.materials_ready(kiln) and WorldAudit.conserved(w), "delivered stone stays at building without duplication")
	var forge := add_ready(w,h,"forge",Vector2i(-12,-7))
	master(w,h,"preservation"); master(w,h,"stonework"); master(w,h,"ceramics"); master(w,h,"metallurgy")
	stock.ore = 2; w.industry.produced.ore += 2
	p.x=forge.x; p.y=forge.y
	WorldEconomy.set_task(w,p,WorldEconomy.task("manufacture",Vector2i(forge.x,forge.y),forge.id))
	p.task.resource="metal"; p.task.started=false
	var wood: int = h.wood
	WorldEconomy.execute(w,p,h)
	check(stock.ore == 0 and h.wood == wood-1 and p.task.started and p.cargo == 0, "smelting consumes inputs once, before work creates output")
	check(copy(w) != null, "partially completed smelting roundtrips")
	for i in 20:
		w.ticks += 1
		if p.task.is_empty(): break
		WorldEconomy.execute(w,p,h)
	check(p.cargo_kind == "metal" and p.cargo == 1 and WorldAudit.conserved(w), "smelting produces finite metal and closes all ledgers")
	var invalid := w.to_dict()
	invalid.civilization.towns[0].stock.ore = -1
	check(WorldState.from_dict(invalid) == null, "negative industrial inventories rejected")
	invalid = w.to_dict(); invalid.climate.settings.scale = 0
	check(WorldState.from_dict(invalid) == null, "invalid climate scale rejected")

	w = WorldState.new()
	w.paint(Vector2i.ZERO,4,WorldState.Terrain.GRASS)
	WorldClimate.configure(w,"belts",0,0,100,true)
	var initial: int = WorldClimate.biome(w,Vector2i(12,50))
	w.paint(Vector2i(100000,100000),1,WorldState.Terrain.GRASS)
	check(WorldClimate.biome(w,Vector2i(12,50)) == initial, "expanding map does not shift climate belts")
	WorldClimate.paint(w,Vector2i.ZERO,2,1)
	w._set_food(Vector2i.ZERO,0); w.regrowth=3
	check(w.food_at(Vector2i.ZERO) == 0, "desert food recovery keeps fractional days")
	w.regrowth=4
	check(w.food_at(Vector2i.ZERO) == 1, "desert recovers one food in four days")
	w.ticks=WorldLife.YEAR*3/4
	check(WorldClimate.season(w) == 3 and WorldClimate.yield_factor(w,Vector2i.ZERO) < .25, "winter reduces harvest without changing biome")
	w.paint(Vector2i(3,0),0,WorldState.Terrain.FOREST)
	WorldClimate.paint(w,Vector2i(3,0),0,0)
	w.harvest_wood(Vector2i(3,0),12)
	w.ticks += WorldLife.YEAR*2
	WorldClimate.step(w)
	check(w.terrain_at(Vector2i(3,0)) == WorldState.Terrain.FOREST and w.wood_at(Vector2i(3,0)) == 12, "forest returns after two years in suitable climate")
	check(copy(w) != null, "climate belts, seasons and painted biome roundtrip")

	w = WorldState.new()
	h = home(w,Vector2i.ZERO)
	var other := home(w,Vector2i(10000,0))
	for key in ["preservation","carpentry","navigation","weaving","sailing"]: master(w,h,key)
	var vessel := add_ready(w,h,"sailboat",Vector2i(11,12))
	var coast := WorldMaritime.shore(w,other,Vector2i.ZERO)
	coast.town = other.id
	var count := w.people.size()
	check(WorldMaritime.launch(w,h,vessel,coast), "sailboat launches across large empty ocean with real crew and provisions")
	if not w.voyages.is_empty():
		var ship: Dictionary = w.voyages[0]
		check(ship.crew.size() == 1 and w.people.size() == count and WorldAudit.conserved(w), "boarding transfers existing people and stock")
		for i in 80:
			w.step()
			if ship.phase == "outbound": break
		var restored := copy(w)
		check(restored != null, "mid-voyage snapshot restores all crew and supplies")
		for i in 80:
			w.step()
			if restored != null: restored.step()
		check(restored != null and JSON.stringify(w.to_dict()) == JSON.stringify(restored.to_dict()), "voyage, storms and production continue identically after loading")
		check(not w.contacts.is_empty() and w.contacts[0].a == h.id and w.contacts[0].b == other.id, "actual arrival establishes first contact")
		check(WorldAudit.conserved(w), "expedition and return conserve all finite inventories")
		invalid=w.to_dict()
		invalid.maritime.fishing=[[0,0,0,7]]
		check(WorldState.from_dict(invalid)==null,"fishing above daily replenishment rejected")
	check(WorldMaritime.route(w,Vector2i(0,30),Vector2i(900000,30)).size()==2,"distant empty ocean uses two waypoints")

	w=WorldState.new(); h=home(w,Vector2i.ZERO)
	other=home(w,Vector2i(50,0),3)
	for x in range(15,36): w.paint(Vector2i(x,0),2,WorldState.Terrain.GRASS)
	p=w.people[0]
	var id: int=p.id
	var birthday: int=p.birth_tick
	check(WorldTravel.launch(w,h,other,[id],"migrate"),"migration starts on connected land with housing and food")
	for i in 10: w.step()
	var resumed := copy(w)
	check(resumed!=null,"overland journey saves in transit outside a home work area")
	for i in 100:
		w.step()
		if resumed!=null: resumed.step()
	check(p.home == other.id and p.birth_tick==birthday and w.people.size()==9,"migrant arrives without cloning or resetting age")
	check(resumed!=null and JSON.stringify(w.to_dict())==JSON.stringify(resumed.to_dict()),"land journey continues identically after loading")
	check(WorldAudit.conserved(w),"overland supplies and relocation conserve resources")

	w=WorldState.new(); h=home(w,Vector2i.ZERO)
	other=home(w,Vector2i(50,0),3)
	for x in range(15,36): w.paint(Vector2i(x,0),2,WorldState.Terrain.GRASS)
	var father: Dictionary=w.people[0]; var mother: Dictionary=w.people[1]
	mother.sex="female"; WorldLife.make_pair(w,father,mother)
	w.add_person(Vector2i.ZERO,false)
	var child: Dictionary=w.people.back(); child.home=h.id; child.birth_tick=-WorldLife.YEAR; child.job="child"; child.generation=2; child.guardian=mother.id; child.parents=[int(mother.id),int(father.id)]; child.ancestors=child.parents.duplicate()
	WorldLife.join(w,child,WorldLife.household(w,mother.household)); WorldLife.reconcile(w)
	check(WorldTravel.launch(w,h,other,[int(father.id),int(mother.id),int(child.id)],"migrate"),"parents and dependent child start one family journey")
	for i in 10: w.step()
	check(copy(w)!=null,"family with a young child saves while travelling")
	for i in 80: w.step()
	check(child.home==other.id and child.guardian==mother.id and child.household==mother.household and child.household==father.household,"family reunites at destination with original parents and guardian")
	check(copy(w)!=null and WorldAudit.conserved(w),"family migration preserves save integrity and all resources")

	w=WorldState.new(); h=home(w,Vector2i.ZERO)
	var teacher: Dictionary=w.people[0]; var student: Dictionary=w.people[1]
	student.skills.build=0
	check(not WorldSocial.eligible(w,student,teacher,"build"),"adult retraining requires a real school")
	add_ready(w,h,"school",Vector2i(-12,7))
	check(WorldSocial.eligible(w,student,teacher,"build") and WorldSocial.offer_lesson(w,student,h),"school opens physical adult lessons")
	for i in 60:
		w.ticks+=1
		if student.lesson.is_empty(): break
		WorldSocial.student_step(w,student,h)
		WorldSocial.teach(w,teacher,h)
	check(student.skills.build>0 and w.metrics.lessons==1 and copy(w)!=null,"adult finishes a lesson and retains the mentor after loading")
	teacher.x=0; teacher.y=0; student.x=1; student.y=0
	var removed: int=h.food; h.food=0; w.metrics.lost_food+=removed
	teacher.hunger=45; student.hunger=45
	for i in 8:
		w.ticks+=WorldEconomy.DAY_TICKS
		WorldSocial.dispute(w,teacher,student,h)
	check(WorldSocial.tension(teacher,student)>=30 and not WorldSocial.eligible(w,student,teacher,"build"),"repeated scarcity can stop collaboration")
	check(copy(w)!=null and WorldAudit.conserved(w),"reciprocal rivalry roundtrips without resource effects")
	invalid=w.to_dict(); invalid.people[0].rivals[0].resentment=-1
	check(WorldState.from_dict(invalid)==null,"invalid rivalry rejected")

	w=WorldState.new(); h=home(w,Vector2i.ZERO)
	w.paint(Vector2i(10000,0),18,WorldState.Terrain.GRASS)
	WorldClimate.paint(w,Vector2i(10000,0),18,2)
	for key in ["preservation","carpentry","navigation","weaving","sailing"]: master(w,h,key)
	var probe: Dictionary={"id":-1,"x":10000,"y":0}
	coast=WorldMaritime.shore(w,probe,Vector2i.ZERO)
	vessel=add_ready(w,h,"sailboat",Vector2i(11,12))
	count=w.people.size()
	check(WorldMaritime.launch(w,h,vessel,coast,"colony"),"three actual settlers can provision a colony")
	for i in 90: w.step()
	check(w.towns.size()==2 and w.people.size()==count,"colony adds a camp without spawning more people")
	check(WorldEconomy.members(w,w.towns[1]).size()==3 and WorldAudit.conserved(w) and copy(w)!=null,"colonists transfer real food and retain saved lives in a different climate")

	w=WorldState.new()
	var sculpt:=WorldSculpt.new()
	check(sculpt.begin(w,Vector2i(800000,700000),Vector2i(64,64),WorldState.Terrain.GRASS),"continent generation starts at distant coordinates")
	while not sculpt.finished: sculpt.advance(2000)
	check(w.walkable(Vector2i(800000,700000)) and w.region_count()<=9 and copy(w)!=null,"sliced continent generation produces a valid sparse saved world")
	sculpt=WorldSculpt.new(); sculpt.begin(w,Vector2i.ZERO,Vector2i(256,256),WorldState.Terrain.GRASS); sculpt.advance(2000); sculpt.cancelled=true; sculpt.advance()
	check(sculpt.finished and sculpt.cursor<sculpt.total and copy(w)!=null,"cancelled generation keeps a valid completed portion")

	w=WorldState.new()
	for i in 300: w.paint(Vector2i(i*64,100),0,WorldState.Terrain.GRASS)
	check(w.region_count()==300 and not w.regions.cold.is_empty() and w.chunks.size()<=WorldRegions.CACHE_LIMIT,"inactive map regions unload while all land remains available")
	var before := JSON.stringify(w.to_dict())
	for i in range(299,-1,-1): check(w.terrain_at(Vector2i(i*64,100))==WorldState.Terrain.GRASS,"cold region retains land %d" % i)
	check(JSON.stringify(w.to_dict())==before,"viewing distant regions does not mutate simulation state")
	var save_path := "user://expansion-acceptance.json"
	check(SaveStore.save_world(w,save_path)==OK,"large world writes regional manifest")
	var loaded := SaveStore.load_world(save_path)
	check(loaded!=null and JSON.stringify(loaded.to_dict())==before,"streamed regional load preserves exact map and clock")
	w.regions.trim(w)
	if not w.regions.cold.is_empty():
		var key: Vector2i=w.regions.cold.keys()[0]
		var file:=FileAccess.open(w.regions.cold[key].path,FileAccess.WRITE)
		file.store_string("damaged cache"); file.close()
		check(w.regions.get_region(w,key).is_empty() and w.regions.failed,"damaged cold cache is detected")
		check(SaveStore.save_world(w,save_path)!=OK and SaveStore.load_world(save_path)!=null,"failed cache cannot replace last good official save")
	print("Expansion: %d checks, %d failures." % [checks,failures])
	quit(1 if failures else 0)

func _initialize() -> void: call_deferred("run")
