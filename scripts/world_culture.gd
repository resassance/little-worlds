class_name WorldCulture
extends RefCounted

const SPEC: Dictionary = preload("res://data/traditions.json").data

static func zeros() -> Dictionary:
	var result := {}
	for key in SPEC: result[key] = 0
	return result

static func state_for(world, home: Dictionary) -> Dictionary:
	if not home.has("culture"):
		home.culture = {"focus":"","strength":0,"candidate":"","streak":0,"scores":zeros(),"activity":zeros(),"month":world.ticks/WorldEconomy.DAY_TICKS}
	return home.culture

static func record(world, home: Dictionary, mode: String, amount: int = 1) -> void:
	if home.is_empty(): return
	var state := state_for(world,home)
	state.activity[mode] = mini(1000,int(state.activity[mode])+amount)

static func practice(world, member: Dictionary, skill: String) -> int:
	var home := WorldEconomy.town(world,member.home)
	if home.is_empty(): return 0
	var kind: String = member.task.get("kind","")
	var mode := ""
	if kind in ["plant","harvest"]: mode = "agrarian"
	elif kind=="herd" and member.task.get("action","")!="hunt": mode = "pastoral"
	elif kind=="fish": mode = "maritime"
	elif kind=="research": mode = "scholarly"
	elif kind in ["build","quarry","manufacture"]: mode = "crafts"
	if mode.is_empty(): return 0
	record(world,home,mode)
	var state: Dictionary = home.culture
	return 1 if state.focus==mode and state.strength>=40 and SPEC[mode].skill==skill and posmod(world.ticks+int(member.id),6)==0 else 0

static func lesson_bonus(home: Dictionary, skill: String) -> int:
	var state: Dictionary = home.get("culture",{})
	var mode: String = state.get("focus","")
	if mode.is_empty() or int(state.get("strength",0))<40: return 0
	return 1 if mode=="scholarly" or SPEC[mode].skill==skill else 0

static func monthly(world, home: Dictionary) -> void:
	var state := state_for(world,home)
	var month: int = world.ticks/WorldEconomy.DAY_TICKS
	if month<=state.month: return
	state.month = month
	var best := ""
	var maximum := 0
	var total := 0
	for mode in SPEC:
		state.scores[mode] = int(state.scores[mode])*3/4+mini(48,int(state.activity[mode]))
		var score: int = state.scores[mode]
		total += score
		if score>maximum: maximum = score; best = mode
	var eligible := maximum>=30 and maximum*100>=maxi(1,total)*35
	if eligible and best!=state.focus and (state.focus.is_empty() or maximum>int(state.scores[state.focus])*5/4):
		if state.candidate==best: state.streak = mini(24,int(state.streak)+1)
		else: state.candidate = best; state.streak = 1
		if state.streak>=3:
			state.focus = best; state.strength = 40; state.candidate = ""; state.streak = 0
			world.log_event("Традиции общины","%s: %s." % [home.name,SPEC[best].name.to_lower()])
	else: state.candidate = ""; state.streak = 0
	if not state.focus.is_empty():
		state.strength = clampi(int(state.strength)+(4 if int(state.activity[state.focus])>=4 else -3),0,100)
	for mode in SPEC: state.activity[mode] = 0

static func inherit(world, child: Dictionary, parent: Dictionary) -> void:
	var source: Dictionary = parent.get("culture",{})
	if source.is_empty() or source.focus.is_empty(): return
	var state := state_for(world,child)
	state.focus = source.focus; state.strength = int(source.strength)/2
	for mode in SPEC: state.scores[mode] = int(source.scores[mode])/2

static func restore(world) -> bool:
	for home in world.towns:
		if not home.has("culture"): continue
		var state: Variant = home.culture
		if not state is Dictionary or state.get("focus") not in SPEC.keys()+[""] or state.get("candidate") not in SPEC.keys()+[""]: return false
		for key in ["strength","streak","month"]:
			if not WorldState._integer(state.get(key)): return false
			state[key] = int(state[key])
		if state.strength<0 or state.strength>100 or state.streak<0 or state.streak>24 or state.month<0 or state.month>world.ticks/WorldEconomy.DAY_TICKS: return false
		for field in ["activity","scores"]:
			if not state.get(field) is Dictionary or state[field].size()!=SPEC.size(): return false
			for mode in SPEC:
				if not WorldState._integer(state[field].get(mode)) or state[field][mode]<0 or state[field][mode]>1000: return false
				state[field][mode] = int(state[field][mode])
	return true
