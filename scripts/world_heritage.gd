class_name WorldHeritage
extends RefCounted

const LIMIT := 256
const FOOTPRINTS := 24
const VISITORS := 32
const PERIODS := 8
const RANGE := 4
var sites: Array[Dictionary] = []
var origins: Array[Dictionary] = []
var couriers: Array[Dictionary] = []
var site_index: Dictionary = {}
var origin_index: Dictionary = {}
var courier_index: Dictionary = {}
var regions: Dictionary = {}
var draw_regions: Dictionary = {}
var site_draw_keys: Dictionary = {}
var site_visit_keys: Dictionary = {}
var archived := 0
var revision := 0
var target_cache: Dictionary = {}
var random := RandomNumberGenerator.new()

func initialize(seed_value: int) -> void:
	random.seed = seed_value ^ 15879173

func origin(world, home: Dictionary, founded: int = -1) -> Dictionary:
	if origin_index.has(home.id): return origin_index[home.id]
	var value := {"town":int(home.id),"founded":founded,"empty":-1,"cause":"Поселение опустело","remains":[],"records":[],"site":-1}
	origins.append(value); origin_index[home.id] = value
	return value

func resident_lost(world, member: Dictionary, cause: String) -> void:
	var state: Dictionary = origin_index.get(member.home,{})
	if state.is_empty():
		var home := WorldEconomy.town(world,member.home)
		if home.is_empty(): return
		state = origin(world,home)
	state.cause = "Последняя потеря жителя: " + cause

func remember_building(world, value: Dictionary) -> void:
	if not value.ready or value.kind in ["boat","sailboat"]: return
	var home := WorldEconomy.town(world,value.town)
	if home.is_empty(): return
	var state := origin(world,home)
	add_remain(state.remains,value)
	if value.kind not in ["archive","school","workshop","forge","kiln","loom"]: return
	var society := WorldSociety.get_society(world,home.id)
	var surviving: Array[String] = []
	for key in WorldSociety.TECH:
		if not society.get("tech",{}).has(key) or not society.tech[key].mastered or state.records.has(key): continue
		if value.kind in ["archive","school"] or WorldSociety.TECH[key].skill in ["wood","build"]: surviving.append(key)
	while state.records.size() < 3 and not surviving.is_empty():
		var chosen := random.randi_range(0,surviving.size()-1)
		state.records.append(surviving[chosen]); surviving.remove_at(chosen)

func add_remain(list: Array, value: Dictionary) -> void:
	for row in list:
		if row[0] == value.x and row[1] == value.y:
			row[2] = value.kind
			return
	if list.size() >= FOOTPRINTS:
		if value.kind not in ["archive","school","workshop","forge","kiln","loom"]: return
		var replace := -1
		for i in list.size():
			if list[i][2] in ["house","farm","camp"]: replace = i; break
		if replace == -1: return
		list.remove_at(replace)
	list.append([int(value.x),int(value.y),str(value.kind)])

func index_site(site: Dictionary) -> void:
	site_index[site.id] = site
	site_visit_keys[site.id] = []
	site_draw_keys[site.id] = []
	var low := WorldState.chunk_of(Vector2i(site.x,site.y)-Vector2i.ONE*RANGE)
	var high := WorldState.chunk_of(Vector2i(site.x,site.y)+Vector2i.ONE*RANGE)
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key := Vector2i(x,y)
			if not regions.has(key): regions[key] = []
			regions[key].append(site.id)
			site_visit_keys[site.id].append(key)
	for row in site.remains: _index_remain(site,row)

func _index_remain(site: Dictionary, row: Array) -> void:
	var first := WorldState.chunk_of(Vector2i(row[0],row[1]))
	var last := WorldState.chunk_of(Vector2i(row[0],row[1])+Vector2i.ONE*(int(WorldEconomy.SIZE[row[2]])-1))
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var key := Vector2i(x,y)
			if not draw_regions.has(key): draw_regions[key] = []
			draw_regions[key].append({"site":site.id,"row":row})
			if not site_draw_keys[site.id].has(key): site_draw_keys[site.id].append(key)

func unindex(site: Dictionary) -> void:
	for key in site_visit_keys.get(site.id,[]):
		regions[key].erase(site.id)
		if regions[key].is_empty(): regions.erase(key)
	for key in site_draw_keys.get(site.id,[]):
		var list: Array = draw_regions.get(key,[])
		for i in range(list.size()-1,-1,-1):
			if list[i].site == site.id: list.remove_at(i)
		if list.is_empty(): draw_regions.erase(key)
	site_visit_keys.erase(site.id); site_draw_keys.erase(site.id); site_index.erase(site.id)

func refresh(world, site: Dictionary) -> void:
	var previous: Array = site_draw_keys.get(site.id,[]).duplicate()
	unindex(site)
	if sites.has(site): index_site(site)
	for key in site_draw_keys.get(site.id,[]):
		if not previous.has(key): previous.append(key)
	for key in previous: world.landscape.bump(key)

func rebuild() -> void:
	site_index.clear(); regions.clear(); draw_regions.clear(); site_draw_keys.clear(); site_visit_keys.clear()
	for site in sites: index_site(site)

func at(cell: Vector2i, radius: int = RANGE) -> Dictionary:
	var best: Dictionary = {}
	var distance := radius*radius+1
	for id in regions.get(WorldState.chunk_of(cell),[]):
		var site: Dictionary = site_index[id]
		var d := cell.distance_squared_to(Vector2i(site.x,site.y))
		if d < distance: best = site; distance = d
	return best

func _lose(world, site: Dictionary) -> void:
	world.metrics.lost_wood += int(site.wood)
	for key in WorldCivilization.GOODS: world.industry.lost[key] += int(site.stock[key])

func _room(world) -> bool:
	if sites.size() < LIMIT: return true
	for site in sites:
		if site.current != -1 or not site.visitors.is_empty() or not site.ideas.is_empty(): continue
		var carried := false
		for parcel in couriers:
			if parcel.site == site.id: carried = true; break
		if carried: continue
		_lose(world,site)
		sites.erase(site); archived = mini(1000000,archived+1); refresh(world,site)
		return true
	archived = mini(1000000,archived+1)
	return false

func abandon(world, home: Dictionary, cause: String) -> Dictionary:
	var state := origin(world,home)
	var site: Dictionary = site_index.get(state.site,{})
	if site.is_empty():
		if not _room(world): return {}
		site = {"id":world.next_id,"name":str(home.name),"x":int(home.x),"y":int(home.y),"periods":[],"remains":[],"visitors":[],"finds":[],"ideas":[],"wood":0,"stock":WorldCivilization.empty_stock(),"current":-1}
		world.next_id += 1
		sites.append(site); index_site(site)
	if not site.periods.is_empty() and site.periods.back().town == home.id and site.periods.back().end == -1:
		site.periods.back().end = world.ticks; site.periods.back().cause = cause
	else:
		if site.periods.size() >= PERIODS: site.periods.pop_front()
		site.periods.append({"town":int(home.id),"name":str(home.name),"start":int(state.founded),"end":world.ticks,"cause":cause})
	site.current = -1
	for row in state.remains: add_remain(site.remains,{"x":row[0],"y":row[1],"kind":row[2]})
	var amount := mini(12-int(site.wood),int(home.wood))
	home.wood -= amount; site.wood += amount
	var stock: Dictionary = world.civilization.get(home.id,{}).get("stock",{})
	for key in stock:
		amount = mini(6-int(site.stock[key]),int(stock[key]))
		stock[key] -= amount; site.stock[key] += amount
	for key in state.records:
		if site.ideas.size() >= 3: break
		if not site.ideas.has(key): site.ideas.append(key)
	refresh(world,site)
	revision += 1
	world.log_event("Место истории","%s: %s. Следы поселения остались на карте." % [home.name,cause.to_lower()])
	return site

func forget_origin(home: Dictionary) -> void:
	var state: Dictionary = origin_index.get(home.id,{})
	origins.erase(state); origin_index.erase(home.id); target_cache.erase(home.id)

func settled(world, home: Dictionary) -> void:
	var state := origin(world,home,world.ticks)
	var site := at(Vector2i(home.x,home.y))
	if site.is_empty() or site.current != -1: return
	site.current = int(home.id); state.site = int(site.id)
	if site.periods.size() >= PERIODS: site.periods.pop_front()
	site.periods.append({"town":int(home.id),"name":str(home.name),"start":world.ticks,"end":-1,"cause":""})
	revision += 1
	world.log_event("Новая жизнь старого места","%s основано у руин %s. Постройки ещё предстоит восстановить." % [home.name,site.name])

func visit(world, member: Dictionary, cell: Vector2i) -> void:
	if regions.is_empty() or member.home == -1: return
	var site := at(cell)
	if site.is_empty() or site.current == member.home: return
	var visitor: Dictionary = {}
	for record in site.visitors:
		if record.town == member.home: visitor = record; break
	if visitor.is_empty():
		if site.visitors.size() >= VISITORS: return
		var home := WorldEconomy.town(world,member.home)
		if home.is_empty(): return
		visitor = {"town":int(home.id),"name":str(home.name),"who":str(member.name),"tick":world.ticks,"attempted":false}
		site.visitors.append(visitor)
		world.log_event("Обнаружены руины","%s из %s обнаружил%s остатки %s." % [member.name,home.name,"а" if member.sex == "female" else "",site.name])
		revision += 1
	if visitor.attempted or not WorldLife.adult(world,member) or member.task.get("kind","") not in ["explore","travel"]: return
	visitor.attempted = true; revision += 1
	if member.cargo == 0:
		var kind := "wood" if site.wood > 0 else ""
		for key in WorldCivilization.GOODS:
			if site.stock[key] > 0: kind = key; break
		if not kind.is_empty():
			var source: Dictionary = site if kind == "wood" else site.stock
			var amount := mini(WorldEconomy.LOAD,int(source[kind]))
			source[kind] -= amount; member.cargo_kind = kind; member.cargo = amount
			if site.finds.size() < 8: site.finds.append({"who":str(member.name),"tick":world.ticks,"kind":kind,"amount":amount})
	if courier_index.has(member.id) or site.ideas.is_empty(): return
	var skill := maxi(int(member.skills.build),int(member.skills.wood))
	if random.randf() > 0.35+minf(0.5,float(skill)/200): return
	var options: Array[int] = []
	for i in site.ideas.size():
		if not member.ideas.has(site.ideas[i]): options.append(i)
	if options.is_empty(): return
	var index: int = options[random.randi_range(0,options.size()-1)]
	var idea: String = site.ideas[index]; site.ideas.remove_at(index)
	var parcel := {"member":int(member.id),"site":int(site.id),"idea":idea,"tick":world.ticks}
	couriers.append(parcel); courier_index[member.id] = parcel
	if site.finds.size() < 8: site.finds.append({"who":str(member.name),"tick":world.ticks,"kind":"record","amount":1,"idea":idea,"status":"carried"})
	world.log_event("Найдена старая запись","%s несёт сведения «%s» из %s. Знание нужно доставить домой." % [member.name,WorldSociety.TECH[idea].name,site.name])

func returned(world, member: Dictionary) -> void:
	if not courier_index.has(member.id) or WorldTravel.away(world,member.id): return
	var home := WorldEconomy.town(world,member.home)
	if home.is_empty() or Vector2i(member.x,member.y) != Vector2i(home.x,home.y): return
	var parcel: Dictionary = courier_index[member.id]
	WorldSociety.remember(member,parcel.idea)
	world.log_event("Запись доставлена","%s: %s прин%s сведения «%s». Освоение требует собственной работы." % [home.name,member.name,"есла" if member.sex == "female" else "ёс",WorldSociety.TECH[parcel.idea].name])
	lost(member.id,true); revision += 1

func lost(id: int, delivered: bool = false) -> void:
	if not courier_index.has(id): return
	var parcel: Dictionary = courier_index[id]
	var site: Dictionary = site_index.get(parcel.site,{})
	for find in site.get("finds",[]):
		if find.kind == "record" and find.idea == parcel.idea and find.tick == parcel.tick and find.status == "carried":
			find.status = "delivered" if delivered else "lost"
	couriers.erase(parcel); courier_index.erase(id)

func research_target(world, home: Dictionary, navigation: Dictionary) -> Vector2i:
	var signature := [revision,world.revision,world.ticks/WorldEconomy.DAY_TICKS,navigation.cells.size()]
	var cached: Dictionary = target_cache.get(home.id,{})
	if cached.get("signature") == signature: return cached.cell
	var cell := _research_target(world,home,navigation)
	target_cache[home.id] = {"signature":signature,"cell":cell}
	return cell

func _research_target(world, home: Dictionary, navigation: Dictionary) -> Vector2i:
	if sites.is_empty(): return WorldState.NO_CELL
	var center := Vector2i(home.x,home.y)
	var low := WorldState.chunk_of(center-Vector2i.ONE*WorldExploration.MAX_RANGE)
	var high := WorldState.chunk_of(center+Vector2i.ONE*WorldExploration.MAX_RANGE)
	var seen := {}
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for id in regions.get(Vector2i(x,y),[]):
				if seen.has(id): continue
				seen[id] = true
				var site: Dictionary = site_index[id]
				if site.current == home.id or site.visitors.size() >= VISITORS: continue
				var known := false
				for visitor in site.visitors:
					if visitor.town == home.id and visitor.attempted: known = true; break
				var cell := Vector2i(site.x,site.y)
				if not known and navigation.parents.has(cell) and not world.fires.has(cell): return cell
	return WorldState.NO_CELL

func restoration(world, home: Dictionary, kind: String, nav: Dictionary, after: int) -> Vector2i:
	var state: Dictionary = origin_index.get(home.id,{})
	var site: Dictionary = site_index.get(state.get("site",-1),{})
	if site.is_empty() or after >= site.remains.size(): return WorldState.NO_CELL
	var row: Array = site.remains[after]
	var cell := Vector2i(row[0],row[1])
	if row[2] == kind and WorldEconomy.valid_site(world,nav.parents,kind,cell): return cell
	return WorldState.NO_CELL

func restored(world, value: Dictionary) -> void:
	var state: Dictionary = origin_index.get(value.town,{})
	var site: Dictionary = site_index.get(state.get("site",-1),{})
	if site.is_empty(): return
	for i in site.remains.size():
		var row: Array = site.remains[i]
		if row[0] == value.x and row[1] == value.y and row[2] == value.kind:
			site.remains.remove_at(i); revision += 1; refresh(world,site)
			world.log_event("На старом основании","%s: восстановлено здание «%s»." % [WorldEconomy.town(world,value.town).name,WorldEconomy.NAMES[value.kind]])
			return

func save() -> Dictionary:
	return {"sites":sites.duplicate(true),"origins":origins.duplicate(true),"couriers":couriers.duplicate(true),"archived":archived,"rng":str(random.state)}

func date(tick: int) -> String:
	return "неизвестно" if tick < 0 else "год %d, месяц %d" % [tick/WorldLife.YEAR+1,(tick/WorldEconomy.DAY_TICKS)%12+1]

func details(site: Dictionary) -> Array:
	var result: Array = []
	for period in site.periods:
		result.append([period.name,"%s → %s\n%s" % [date(period.start),date(period.end) if period.end >= 0 else "заселено",period.cause]])
	for visitor in site.visitors: result.append(["Открытие · "+visitor.name,"%s · %s" % [visitor.who,date(visitor.tick)]])
	for find in site.finds:
		if find.kind == "record": result.append(["Запись · "+WorldSociety.TECH[find.idea].name,"%s · %s · %s" % [find.who,date(find.tick),{"carried":"в пути","delivered":"доставлена","lost":"утрачена в пути"}[find.status]]])
		else: result.append(["Находка · "+find.who,"%s: %d · %s" % ["Древесина" if find.kind == "wood" else WorldCivilization.GOODS[find.kind],find.amount,date(find.tick)]])
	if site.visitors.is_empty(): result.append(["Пока не исследовано","Общины узнают о месте после посещения."])
	return result

func restore(world, data: Variant) -> bool:
	initialize(world.world_seed)
	if data == null: return true
	if not data is Dictionary or not data.get("sites") is Array or data.sites.size() > LIMIT or not data.get("origins") is Array or data.origins.size() > WorldState.MAX_PEOPLE or not data.get("couriers") is Array or data.couriers.size() > WorldState.MAX_PEOPLE: return false
	if not WorldState._integer(data.get("archived")) or data.archived < 0 or data.archived > 1000000 or not data.get("rng") is String or not data.rng.is_valid_int(): return false
	var used := {}
	for collection in [world.people,world.towns,world.buildings,world.societies,world.households,world.ancestry_archive,world.voyages,world.journeys]:
		for value in collection: used[int(value.id)] = true
	for item in data.sites:
		if not item is Dictionary: return false
		for field in ["id","x","y","wood","current"]:
			if not WorldState._integer(item.get(field)): return false
		if item.id <= 0 or item.id >= world.next_id or used.has(int(item.id)) or not _point(world,item.x,item.y) or item.wood < 0 or item.wood > 12 or not _text(item.get("name")): return false
		if item.current != -1 and WorldEconomy.town(world,int(item.current)).is_empty(): return false
		for field in ["periods","remains","visitors","finds","ideas"]:
			if not item.get(field) is Array: return false
		if item.periods.is_empty() or item.periods.size() > PERIODS or item.remains.size() > FOOTPRINTS or item.visitors.size() > VISITORS or item.finds.size() > 8 or item.ideas.size() > 3: return false
		if not item.get("stock") is Dictionary or item.stock.size() != WorldCivilization.GOODS.size(): return false
		for key in WorldCivilization.GOODS:
			if not WorldState._integer(item.stock.get(key)) or item.stock[key] < 0 or item.stock[key] > 6: return false
		var period_ids := {}
		var last_end := -1
		for period in item.periods:
			if not period is Dictionary or not _text(period.get("name")) or not _text(period.get("cause"),true): return false
			for field in ["town","start","end"]:
				if not WorldState._integer(period.get(field)): return false
			if period.town <= 0 or period.town >= world.next_id or period_ids.has(int(period.town)) or not _time(world,period.start,true) or not _time(world,period.end,true): return false
			if period.start >= 0 and (period.start < last_end or (period.end >= 0 and period.end < period.start)): return false
			if period.end == -1 and (period != item.periods.back() or period.town != item.current): return false
			period_ids[int(period.town)] = true; last_end = int(period.end)
		var visitor_ids := {}
		for visitor in item.visitors:
			if not visitor is Dictionary or not _text(visitor.get("name")) or not _text(visitor.get("who")) or not WorldState._integer(visitor.get("town")) or visitor.town <= 0 or visitor.town >= world.next_id or visitor_ids.has(int(visitor.town)) or not _time(world,visitor.get("tick")) or not visitor.get("attempted") is bool: return false
			visitor_ids[int(visitor.town)] = true
		for find in item.finds:
			if not find is Dictionary or not _text(find.get("who")) or not _time(world,find.get("tick")) or not WorldState._integer(find.get("amount")) or find.amount < 1 or find.amount > WorldEconomy.LOAD: return false
			if find.get("kind") == "record":
				if not WorldSociety.TECH.has(find.get("idea")) or find.get("status") not in ["carried","delivered","lost"] or find.amount != 1: return false
			elif find.get("kind") != "wood" and not WorldCivilization.GOODS.has(find.get("kind")): return false
		var ideas_seen := {}
		for idea in item.ideas:
			if not WorldSociety.TECH.has(idea) or ideas_seen.has(idea): return false
			ideas_seen[idea] = true
		if not _remains(world,item.remains): return false
		var site: Dictionary = item.duplicate(true)
		for field in ["id","x","y","wood","current"]: site[field] = int(site[field])
		for key in site.stock: site.stock[key] = int(site.stock[key])
		for row in site.remains: row[0] = int(row[0]); row[1] = int(row[1])
		for field in ["periods","visitors","finds"]:
			for row in site[field]:
				for key in row:
					if row[key] is float: row[key] = int(row[key])
		sites.append(site); used[site.id] = true; index_site(site)
	for item in data.origins:
		if not item is Dictionary: return false
		for field in ["town","founded","empty","site"]:
			if not WorldState._integer(item.get(field)): return false
		if WorldEconomy.town(world,int(item.town)).is_empty() or origin_index.has(int(item.town)) or not _time(world,item.founded,true) or not _time(world,item.empty,true): return false
		if item.site != -1 and (not site_index.has(int(item.site)) or site_index[int(item.site)].current != item.town): return false
		if not item.get("records") is Array or item.records.size() > 3: return false
		var records := {}
		for key in item.records:
			if not WorldSociety.TECH.has(key) or records.has(key): return false
			records[key] = true
		if not item.get("remains") is Array or not _remains(world,item.remains): return false
		var value: Dictionary = item.duplicate(true)
		for field in ["town","founded","empty","site"]: value[field] = int(value[field])
		if not _text(value.get("cause")): return false
		for row in value.remains: row[0] = int(row[0]); row[1] = int(row[1])
		origins.append(value); origin_index[value.town] = value
	for site in sites:
		if site.current != -1 and origin_index.get(site.current,{}).get("site",-1) != site.id: return false
	for item in data.couriers:
		if not item is Dictionary: return false
		for field in ["member","site","tick"]:
			if not WorldState._integer(item.get(field)): return false
		if WorldLife.person(world,int(item.member)).is_empty() or courier_index.has(int(item.member)) or not site_index.has(int(item.site)) or not WorldSociety.TECH.has(item.get("idea")) or not _time(world,item.tick): return false
		var parcel: Dictionary = item.duplicate()
		for field in ["member","site","tick"]: parcel[field] = int(parcel[field])
		couriers.append(parcel); courier_index[parcel.member] = parcel
	archived = int(data.archived); random.state = data.rng.to_int()
	return true

func _remains(world, list: Array) -> bool:
	if list.size() > FOOTPRINTS: return false
	var seen := {}
	for row in list:
		if not row is Array or row.size() != 3 or not _point(world,row[0],row[1]) or not WorldEconomy.SIZE.has(row[2]) or row[2] in ["boat","sailboat"]: return false
		var cell := Vector2i(row[0],row[1])
		if seen.has(cell): return false
		seen[cell] = true
	return true

func _point(world, x: Variant, y: Variant) -> bool:
	return WorldState._integer(x) and WorldState._integer(y) and absf(float(x)) <= WorldState.COORD_LIMIT and absf(float(y)) <= WorldState.COORD_LIMIT and world.inside(Vector2i(x,y))

func _time(world, value: Variant, unknown: bool = false) -> bool:
	return WorldState._integer(value) and value >= (-1 if unknown else 0) and value <= world.ticks

func _text(value: Variant, empty: bool = false) -> bool:
	return value is String and value.length() <= 256 and (empty or not value.is_empty())
