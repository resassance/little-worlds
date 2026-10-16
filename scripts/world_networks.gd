class_name WorldNetworks
extends RefCounted

const LIMIT := 128
const MAX_ROUTE := 256
const STAGES := ["Лагерь","Деревня","Посад","Город","Промышленный город","Мегаполис"]
const BUILD_TECH := {"bridge":"carpentry","irrigation":"waterworks","townhouse":"masonry","mill":"mechanization","factory":"steam","power":"electricity","apartment":"urbanism","tower":"highrise"}
var towns: Array[Dictionary] = []
var links: Array[Dictionary] = []
var town_index: Dictionary = {}
var link_index: Dictionary = {}
var neighbors: Dictionary = {}
var bridges: Dictionary = {}
var bridge_records: Dictionary = {}
var bridge_valid: Dictionary = {}
var roads: Dictionary = {}
var infrastructure_regions: Dictionary = {}
var revision := 0
var navigation_queue: Array[int] = []

func state_for(world, home: Dictionary) -> Dictionary:
	if town_index.has(home.id): return town_index[home.id]
	var state := {"town":int(home.id),"parent":-1,"parent_name":"","founded":int(world.heritage.origin_index.get(home.id,{}).get("founded",-1)),"pressure":0,"stage":0,"power_until":0,"next_migration":world.ticks,"neighbor_cursor":0,"project":""}
	towns.append(state); town_index[home.id] = state
	return state

func pair(a: int,b: int) -> Vector2i:
	return Vector2i(mini(a,b),maxi(a,b))

func relation(a: int,b: int) -> Dictionary:
	return link_index.get(pair(a,b),{})

func link_towns(world, a: Dictionary,b: Dictionary, mode: String = "land",route: Array = []) -> Dictionary:
	if a.is_empty() or b.is_empty() or a.id == b.id: return {}
	var key := pair(a.id,b.id)
	if link_index.has(key): return link_index[key]
	if links.size() >= LIMIT: return {}
	var link := {"a":key.x,"b":key.y,"trust":50,"deliveries":0,"failures":0,"aid":0,"cargo":0,"kind":"","last_tick":world.ticks,"blocked_until":0,"mode":mode,"route":route.duplicate(true) if route.size() <= MAX_ROUTE else [],"reason":"Первый контакт"}
	links.append(link); link_index[key] = link
	for id in [key.x,key.y]:
		if not neighbors.has(id): neighbors[id] = []
		neighbors[id].append(link)
	revision += 1
	return link

func status(link: Dictionary, tick: int) -> String:
	if int(link.blocked_until) > tick: return "Обмен приостановлен"
	if link.trust >= 70 and link.deliveries >= 2: return "Союз"
	if link.trust < 35: return "Спор"
	return "Добрососедство" if link.deliveries > 0 else "Знакомство"

func permitted(a: int,b: int,tick: int) -> bool:
	var link := relation(a,b)
	return link.is_empty() or int(link.blocked_until) <= tick

func amount(world, home: Dictionary, kind: String) -> int:
	if home.is_empty(): return 0
	return int(home[kind]) if kind in ["food","wood"] else int(world.civilization.get(home.id,{}).get("stock",{}).get(kind,0))

func capacity(world, home: Dictionary, kind: String) -> int:
	if kind == "food": return WorldEconomy.food_capacity(world,home)
	if kind == "wood": return WorldEconomy.wood_capacity(world,home)
	return WorldCivilization.CAPACITY

func stock_goal(world, home: Dictionary, kind: String) -> int:
	var advanced := WorldSociety.mastered(world,home,"urbanism")
	if kind == "stone": return 56 if WorldSociety.mastered(world,home,"highrise") else (36 if advanced else 24)
	if kind == "metal": return 32 if advanced else 12
	if kind == "tools": return 16 if advanced else 8
	if kind == "ore": return 20 if advanced else 12
	return 12

func need(world, home: Dictionary, kind: String) -> int:
	if kind == "food": return maxi(0,mini(WorldEconomy.food_capacity(world,home),ceili(WorldEconomy.daily_need(world,home)*12))-int(home.food))
	if kind == "wood": return maxi(0,32-int(home.wood))
	return maxi(0,stock_goal(world,home,kind)-amount(world,home,kind))

func spare(world, home: Dictionary, kind: String) -> int:
	var keep := 12
	if kind == "food": keep = maxi(8,ceili(WorldEconomy.daily_need(world,home)*6))
	elif kind != "wood": keep = 4
	return maxi(0,amount(world,home,kind)-keep)

func offer(world, source: Dictionary,target: Dictionary) -> Dictionary:
	if source.is_empty() or target.is_empty(): return {}
	var link := relation(source.id,target.id)
	var emergency := WorldEconomy.food_days(world,target) < 2 and WorldEconomy.food_days(world,source) >= 12
	if not emergency and not permitted(source.id,target.id,world.ticks): return {}
	var choices: Array = ["food","wood"]+WorldCivilization.GOODS.keys()
	var selected := ""
	var best := 0.0
	for kind in choices:
		var room := capacity(world,target,kind)-amount(world,target,kind)
		if room < 1 or spare(world,source,kind) < 3: continue
		var deficit := need(world,target,kind)
		if deficit <= 0: continue
		var score := minf(2.0,float(deficit)/12)
		if kind == "food" and WorldEconomy.food_days(world,target)<4: score += 4
		elif kind == "wood" and target.wood < 6: score += 2
		if score > best: selected = kind; best = score
	if selected.is_empty(): return {}
	var count := mini(6,mini(spare(world,source,selected),capacity(world,target,selected)-amount(world,target,selected)))
	if emergency and selected == "food": return {"kind":selected,"amount":count,"return_kind":"","return_amount":0,"aid":true}
	var payment := ""
	best = -1.0
	for kind in choices:
		if kind == selected or spare(world,target,kind) < 3 or capacity(world,source,kind)-amount(world,source,kind)<3: continue
		var score := float(need(world,source,kind))
		if score > best: payment = kind; best = score
	if payment.is_empty():
		if not link.is_empty() and link.trust >= 70 and WorldEconomy.food_days(world,source) >= 12:
			return {"kind":selected,"amount":count,"return_kind":"","return_amount":0,"aid":true}
		return {}
	return {"kind":selected,"amount":count,"return_kind":payment,"return_amount":3,"aid":false}

func take(world, home: Dictionary, kind: String, count: int) -> void:
	if kind in ["food","wood"]: home[kind] -= count
	else: WorldCivilization.ensure(world,home).stock[kind] -= count

func put(world, home: Dictionary, kind: String, count: int) -> void:
	if kind in ["food","wood"]: home[kind] += count
	else: WorldCivilization.ensure(world,home).stock[kind] += count

func exchange(world, shipment: Dictionary, source: Dictionary,target: Dictionary,mode: String) -> bool:
	if source.is_empty() or target.is_empty() or shipment.cargo <= 0: return false
	var kind: String = shipment.cargo_kind
	var count: int = shipment.cargo
	var payment: String = shipment.get("return_kind","")
	var price: int = shipment.get("return_amount",0)
	if capacity(world,target,kind)-amount(world,target,kind)<count: return false
	if not payment.is_empty() and (not permitted(source.id,target.id,world.ticks) or amount(world,target,payment)<price): return false
	put(world,target,kind,count)
	if price > 0: take(world,target,payment,price)
	shipment.cargo = price; shipment.cargo_kind = payment if price > 0 else ""
	var link := link_towns(world,source,target,mode,shipment.get("route",[]) if mode == "land" else [])
	if not link.is_empty():
		link.mode = mode
		if mode=="land" and shipment.get("route",[]).size()<=MAX_ROUTE: link.route = shipment.route.duplicate(true)
		link.trust = mini(100,int(link.trust)+(10 if shipment.purpose == "aid" else 5))
		link.deliveries += 1; link.last_tick = world.ticks; link.cargo += count; link.kind = kind
		link.reason = "Помощь при нехватке припасов" if shipment.purpose == "aid" else "Взаимная поставка"
		if shipment.purpose == "aid": link.aid += 1
		link.blocked_until = 0
	world.log_event("Помощь доставлена" if shipment.purpose == "aid" else "Торговая поставка","%s → %s: %d · %s." % [source.name,target.name,count,{"food":"еда","wood":"древесина"}.get(kind,WorldCivilization.GOODS.get(kind,kind))])
	revision += 1
	return true

func failed(world, shipment: Dictionary, reason: String) -> void:
	var link := relation(int(shipment.home),int(shipment.get("target",-1)))
	if link.is_empty(): return
	link.failures += 1; link.trust = maxi(0,int(link.trust)-8); link.reason = reason; link.last_tick = world.ticks
	if link.failures >= 2 and link.trust < 40: link.blocked_until = world.ticks+WorldEconomy.DAY_TICKS*3
	revision += 1

func powered(world, home: Dictionary) -> bool:
	return int(town_index.get(home.id,{}).get("power_until",0)) > world.ticks and WorldEconomy.count(world,home,"power") > 0

func housing_kind(world, home: Dictionary) -> String:
	for kind in ["tower","apartment","townhouse"]:
		if not WorldDevelopment.construction_ready(world,home,kind) or WorldEconomy.available_wood(world,home)<int(WorldEconomy.COST[kind]): continue
		if not WorldCivilization.inputs_available(world,home,WorldCivilization.EXTRA.get(kind,{})): continue
		return kind
	return "house"

func construction_ready(world, home: Dictionary, kind: String) -> bool:
	if BUILD_TECH.has(kind) and not WorldSociety.mastered(world,home,BUILD_TECH[kind]): return false
	if kind == "tower" and not powered(world,home): return false
	if kind in ["factory","power","apartment","tower"] and WorldEconomy.members(world,home).size() < 12: return false
	return true

func bridge_open(world, cell: Vector2i) -> bool:
	if not bridges.has(cell): return false
	var value: Dictionary = bridges[cell]
	var cached: Dictionary = bridge_valid.get(value.id,{})
	if cached.get("revision",-1) != world.path_revision:
		var span: Array = value.get("project_cells",[])
		if span.is_empty(): return false
		var end := Vector2i(span.back()[0],span.back()[1])
		var first := Vector2i(value.x,value.y)
		var valid: bool = value.get("ready",false) and world.terrain_at(first) in [WorldState.Terrain.GRASS,WorldState.Terrain.SAND,WorldState.Terrain.FOREST] and world.terrain_at(end) in [WorldState.Terrain.GRASS,WorldState.Terrain.SAND,WorldState.Terrain.FOREST]
		for row in span:
			if world.terrain_at(Vector2i(row[0],row[1])) == WorldState.Terrain.MOUNTAIN: valid = false
		cached = {"revision":world.path_revision,"valid":valid}; bridge_valid[value.id] = cached
	return cached.valid

func completed(world, value: Dictionary) -> void:
	_index_infrastructure(world,value,true)
	if value.kind == "bridge":
		for row in value.get("project_cells",[]): bridges[Vector2i(row[0],row[1])] = value
		bridge_records[value.id] = value; bridge_valid.erase(value.id)
		world.path_revision += 1
		_navigation_changed(world,value); world.site_cache.clear()
	elif value.kind == "roadworks":
		for row in value.get("project_cells",[]): roads[Vector2i(row[0],row[1])] = value.id
	if value.kind in ["bridge","roadworks","irrigation","plaza","embankment"]:
		world.log_event("Общий проект завершён","%s: %s." % [WorldEconomy.town(world,value.town).name,WorldEconomy.NAMES[value.kind]])
		for link in neighbors.get(value.town,[]): link.trust = mini(100,int(link.trust)+2)
	revision += 1

func removed(world, value: Dictionary) -> void:
	_index_infrastructure(world,value,false)
	if value.kind == "bridge":
		for row in value.get("project_cells",[]): bridges.erase(Vector2i(row[0],row[1]))
		bridge_records.erase(value.id); bridge_valid.erase(value.id)
		world.path_revision += 1; _navigation_changed(world,value)
	elif value.kind == "roadworks":
		for row in value.get("project_cells",[]): roads.erase(Vector2i(row[0],row[1]))
	revision += 1

func pave(world, cell: Vector2i) -> bool:
	return roads.has(cell) and world.building_index.has(roads[cell])

func ancestry(world, child: Dictionary, parent: Dictionary, mode: String = "land") -> void:
	var state := state_for(world,child)
	state.parent = int(parent.id); state.parent_name = str(parent.name)
	link_towns(world,parent,child,mode)
	world.log_event("Дочернее поселение","%s основано переселенцами из %s." % [child.name,parent.name])

func save() -> Dictionary:
	return {"towns":towns.duplicate(true),"links":links.duplicate(true)}

func valid_project(world, value: Dictionary) -> bool:
	var cells: Variant = value.get("project_cells",[])
	if not cells is Array or cells.size()>32: return false
	var seen := {}
	for row in cells:
		if not WorldMaritime.valid_point(world,row): return false
		var cell := Vector2i(row[0],row[1])
		if seen.has(cell): return false
		seen[cell] = true
	if value.get("kind") != "bridge": return true
	if cells.size()<2 or cells.size()>5: return false
	var anchor := Vector2i(value.x,value.y)
	var direction := Vector2i(cells[0][0],cells[0][1])-anchor
	if direction.length_squared()!=1: return false
	for i in cells.size():
		if Vector2i(cells[i][0],cells[i][1])!=anchor+direction*(i+1): return false
	return true

func prepare_bridges(world, source: Variant) -> bool:
	if not source is Array or source.size()>WorldState.MAX_BUILDINGS: return false
	for value in source:
		if not value is Dictionary: return false
		if value.get("kind") not in ["bridge","roadworks"]: continue
		for key in ["id","x","y"]:
			if not WorldState._integer(value.get(key)): return false
		if not WorldMaritime.valid_point(world,[value.x,value.y]) or not valid_project(world,value): return false
		if not value.get("ready") is bool: return false
		if value.ready and value.kind=="bridge":
			for row in value.project_cells:
				var cell := Vector2i(row[0],row[1])
				if bridges.has(cell): return false
				bridges[cell] = value
	return true

func restore(world, source: Variant) -> bool:
	bridges.clear(); bridge_records.clear(); bridge_valid.clear(); roads.clear(); infrastructure_regions.clear()
	for value in world.buildings:
		if value.kind not in ["bridge","roadworks"]: continue
		if not valid_project(world,value): return false
		for row in value.project_cells:
			for i in 2: row[i] = int(row[i])
		if not value.ready: continue
		_index_infrastructure(world,value,true)
		for row in value.project_cells:
			var cell := Vector2i(row[0],row[1])
			if value.kind=="bridge": bridges[cell] = value
			else: roads[cell] = value.id
		if value.kind=="bridge": bridge_records[value.id] = value
	if source == null: return true
	if not source is Dictionary or not source.get("towns") is Array or source.towns.size()>WorldState.MAX_PEOPLE or not source.get("links") is Array or source.links.size()>LIMIT: return false
	for raw in source.towns:
		if not raw is Dictionary: return false
		for key in ["town","parent","founded","pressure","stage","power_until","next_migration","neighbor_cursor"]:
			if not WorldState._integer(raw.get(key)): return false
		if WorldEconomy.town(world,raw.town).is_empty() or town_index.has(int(raw.town)): return false
		if raw.parent < -1 or raw.parent==raw.town or raw.parent>=world.next_id or not raw.get("parent_name") is String or raw.parent_name.length()>120: return false
		if raw.founded< -1 or raw.founded>world.ticks or raw.pressure<0 or raw.pressure>100 or raw.stage<0 or raw.stage>=STAGES.size(): return false
		if raw.power_until<0 or raw.power_until>world.ticks+WorldEconomy.DAY_TICKS or raw.next_migration<0 or raw.next_migration>world.ticks+WorldLife.YEAR or raw.neighbor_cursor<0 or raw.neighbor_cursor>=81: return false
		if not raw.get("project") is String or (raw.project!="" and not WorldEconomy.COST.has(raw.project)): return false
		var state: Dictionary = raw.duplicate(true)
		for key in ["town","parent","founded","pressure","stage","power_until","next_migration","neighbor_cursor"]: state[key] = int(state[key])
		towns.append(state); town_index[state.town] = state
	for raw in source.links:
		if not raw is Dictionary: return false
		for key in ["a","b","trust","deliveries","failures","aid","cargo","last_tick","blocked_until"]:
			if not WorldState._integer(raw.get(key)): return false
		if raw.a>=raw.b or WorldEconomy.town(world,raw.a).is_empty() or WorldEconomy.town(world,raw.b).is_empty() or link_index.has(pair(raw.a,raw.b)): return false
		if raw.trust<0 or raw.trust>100 or raw.deliveries<0 or raw.failures<0 or raw.aid<0 or raw.aid>raw.deliveries or raw.cargo<0 or raw.last_tick<0 or raw.last_tick>world.ticks or raw.blocked_until<0 or raw.blocked_until>world.ticks+WorldLife.YEAR: return false
		if raw.get("mode") not in ["land","sea"] or not raw.get("reason") is String or raw.reason.length()>240 or not raw.get("kind") is String or raw.kind not in ["","food","wood"] and not WorldCivilization.GOODS.has(raw.kind): return false
		if not raw.get("route") is Array or raw.route.size()>MAX_ROUTE: return false
		for i in raw.route.size():
			if not WorldMaritime.valid_point(world,raw.route[i]): return false
			if i>0 and Vector2i(raw.route[i][0],raw.route[i][1]).distance_squared_to(Vector2i(raw.route[i-1][0],raw.route[i-1][1]))!=1: return false
		var link: Dictionary = raw.duplicate(true)
		for key in ["a","b","trust","deliveries","failures","aid","cargo","last_tick","blocked_until"]: link[key] = int(link[key])
		for row in link.route:
			for i in 2: row[i] = int(row[i])
		links.append(link); link_index[pair(link.a,link.b)] = link
		for id in [link.a,link.b]:
			if not neighbors.has(id): neighbors[id] = []
			neighbors[id].append(link)
	return true

static func valid_terms(value: Dictionary) -> bool:
	if not value.get("return_kind","") is String or not WorldState._integer(value.get("return_amount",0)): return false
	var kind: String = value.get("return_kind","")
	var count: int = value.get("return_amount",0)
	return count>=0 and count<=6 and ((count==0)==kind.is_empty()) and (kind in ["","food","wood"] or WorldCivilization.GOODS.has(kind)) and (value.get("purpose")!="aid" or count==0)

func _index_infrastructure(world, value: Dictionary, add: bool) -> void:
	if value.kind not in ["bridge","roadworks"] or not value.ready: return
	for row in value.get("project_cells",[]):
		var cell := Vector2i(row[0],row[1])
		var key := WorldState.chunk_of(cell)
		if add:
			if not infrastructure_regions.has(key): infrastructure_regions[key] = {}
			infrastructure_regions[key][cell] = value
		elif infrastructure_regions.has(key):
			infrastructure_regions[key].erase(cell)
			if infrastructure_regions[key].is_empty(): infrastructure_regions.erase(key)
		world.landscape.bump(key)

func forget_home(id: int) -> void:
	var state: Dictionary = town_index.get(id,{})
	if not state.is_empty(): towns.erase(state); town_index.erase(id)
	for link in neighbors.get(id,[]).duplicate():
		link_index.erase(pair(link.a,link.b)); links.erase(link)
		neighbors.get(link.b if link.a==id else link.a,[]).erase(link)
	neighbors.erase(id); revision += 1

func _navigation_changed(world, value: Dictionary) -> void:
	var retired := {}
	var anchor := Vector2i(value.x,value.y)
	for id in world.navigation:
		var nav: Dictionary = world.navigation[id]
		if nav.has("origin") and absi(anchor.x-nav.origin.x)+absi(anchor.y-nav.origin.y)>int(nav.reach)+6: continue
		retired[id] = nav
	for id in retired:
		world.navigation.erase(id)
		if world.stepping and not navigation_queue.has(int(id)): navigation_queue.append(int(id))
	if not retired.is_empty(): world.navigation_cleanup.append(WorldNavigationCleanupJob.new(retired))
