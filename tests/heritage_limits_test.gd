extends SceneTree

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func abandon(world: WorldState, point: Vector2i, known: bool = false) -> Dictionary:
	world._set_terrain(point,WorldState.Terrain.GRASS)
	var home := {"id":world.next_id,"name":"Очаг %d" % world.next_id,"x":point.x,"y":point.y,"food":0,"wood":1,"level":1}
	world.next_id += 1; world.towns.append(home); world.metrics.harvested_wood += 1
	world.heritage.origin(world,home,world.ticks)
	world.heritage.add_remain(world.heritage.origin_index[home.id].remains,{"x":point.x,"y":point.y,"kind":"camp"})
	var result := world.heritage.abandon(world,home,"Поселение опустело")
	world.metrics.lost_wood += home.wood
	world.towns.erase(home); world.heritage.forget_origin(home)
	if known and not result.is_empty(): result.visitors.append({"town":home.id,"name":home.name,"who":"Исследователь","tick":world.ticks,"attempted":true})
	return result

func _initialize() -> void:
	var world := WorldState.new()
	for i in WorldHeritage.LIMIT: abandon(world,Vector2i(i*64,0),i == 0)
	var significant: int = world.heritage.sites[0].id
	var old: int = world.heritage.sites[1].id
	var before := Time.get_ticks_usec()
	abandon(world,Vector2i(-64,0))
	var cap_usec := Time.get_ticks_usec()-before
	check(world.heritage.sites.size() == WorldHeritage.LIMIT,"historical record count remains bounded")
	check(world.heritage.site_index.has(significant) and not world.heritage.site_index.has(old),"known historical places survive replacement of minor remains")
	check(world.heritage.archived == 1 and WorldAudit.conserved(world),"archiving accounts for all remaining materials")
	check(world.heritage.at(Vector2i(64,0)).is_empty(),"archiving removes spatial visit entries")
	check(not world.heritage.draw_regions.has(Vector2i(2,0)),"archiving removes stale render entries")
	world.add_person(Vector2i.ZERO,false)
	var member: Dictionary = world.people[0]
	var original := world.heritage.save()
	var reads := world.regions.cold_reads
	var maximum := 0
	for i in 2000:
		member.x = 50000+i
		var started := Time.get_ticks_usec()
		world.heritage.visit(world,member,Vector2i(member.x,member.y))
		maximum = maxi(maximum,Time.get_ticks_usec()-started)
	check(world.heritage.save() == original,"movement outside sites does not change historical data or RNG")
	check(world.regions.cold_reads == reads,"historical visits never load uninhabited terrain")
	member.x = 0
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	var loaded := WorldState.from_dict(saved)
	check(loaded != null,"maximum historical collection survives save validation")
	var home := {"id":world.next_id,"name":"Новый очаг","x":0,"y":0,"food":0,"wood":0,"level":1}
	world.next_id += 1; world.towns.append(home)
	world.heritage.settled(world,home)
	for generation in 12:
		world.ticks += WorldEconomy.DAY_TICKS
		world.heritage.abandon(world,home,"Поселение опустело")
		world.heritage.forget_origin(home); world.towns.erase(home)
		home = {"id":world.next_id,"name":"Новый очаг %d" % generation,"x":0,"y":0,"food":0,"wood":0,"level":1}
		world.next_id += 1; world.towns.append(home); world.heritage.settled(world,home)
	check(world.heritage.sites[0].periods.size() == WorldHeritage.PERIODS,"many generations keep bounded chronological history")
	world.people[0].x = 0
	WorldEconomy.add_building(world,home,"camp",Vector2i.ZERO,true)
	check(WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict()))) != null,"bounded multi-generation history remains loadable")
	print("Heritage limits: ",checks," checks, ",failures," failures; cap operation ",cap_usec," us, offsite visit max ",maximum," us")
	quit(1 if failures else 0)
