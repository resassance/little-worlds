class_name WorldAppearanceJob
extends RefCounted

const JOB_DOMAINS := {"farmer": "food", "forager": "food", "fisher": "maritime", "sailor": "maritime", "logger": "engineering", "builder": "engineering", "miner": "materials", "artisan": "materials", "teacher": "education", "researcher": "education", "merchant": "trade"}
const JOB_SKILLS := {"forager": "food", "logger": "wood", "builder": "build", "farmer": "farm", "miner": "build", "artisan": "build", "fisher": "food"}
const BUILDING_DOMAINS := {"farm": "food", "dock": "maritime", "port": "maritime", "boat": "maritime", "sailboat": "maritime", "workshop": "engineering", "kiln": "materials", "loom": "materials", "forge": "materials", "school": "education", "archive": "education", "market": "trade"}
const COLORS := {"food": Color("a4bb75"), "maritime": Color("8bbfc7"), "engineering": Color("c8ad83"), "materials": Color("cd9278"), "education": Color("b4a6c7"), "trade": Color("d1b573"), "mixed": Color("dbc39a")}
var world: WorldState
var people_index := 0
var building_index := 0
var town_index := 0
var phase := 0
var finished := false
var scores := {}
var residents := {}
var counts := {}
var activity := {}
var towns := {}
var working := {}
var outfits := {}
var outfit_ids: Array = []
var outfit_index := 0
var previous_styles := {}
var candidates := {}
var candidate_ids: Array = []
var candidate_index := 0

func _init(value: WorldState, cached_outfits: Dictionary = {}, previous: Dictionary = {}, pending: Dictionary = {}) -> void:
	world = value
	outfits = cached_outfits
	outfit_ids = outfits.keys()
	previous_styles = previous
	candidates = pending
	candidate_ids = candidates.keys()

func advance(budget_usec: int = 200) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func add(town: int, domain: String, amount: float) -> void:
	if not scores.has(town): scores[town] = {}
	scores[town][domain] = float(scores[town].get(domain, 0.0)) + amount

func unit() -> void:
	if phase == 0:
		if people_index >= world.people.size(): phase = 1; return
		var member: Dictionary = world.people[people_index]
		people_index += 1
		residents[member.home] = int(residents.get(member.home, 0)) + 1
		if JOB_DOMAINS.has(member.job) and WorldLife.adult(world, member):
			var domain: String = JOB_DOMAINS[member.job]
			var experience := WorldSocial.level(member, JOB_SKILLS[member.job]) if JOB_SKILLS.has(member.job) else 0
			add(member.home, domain, 0.5 + float(experience) * 0.2)
			if not activity.has(member.home): activity[member.home] = {}
			activity[member.home][domain] = true
		var task: Dictionary = member.task
		if task.get("kind", "") == "manufacture" and task.get("work", 0) > 0: working[int(task.building)] = true
		return
	if phase == 1:
		if building_index >= world.buildings.size(): phase = 2; return
		var value: Dictionary = world.buildings[building_index]
		building_index += 1
		if not value.ready or not BUILDING_DOMAINS.has(value.kind): return
		var domain: String = BUILDING_DOMAINS[value.kind]
		add(value.town, domain, 2.0)
		if not counts.has(value.town): counts[value.town] = {}
		counts[value.town][domain] = int(counts[value.town].get(domain, 0)) + 1
		if value.kind == "farm" and (value.planted or int(value.stock) > 0):
			if not activity.has(value.town): activity[value.town] = {}
			activity[value.town][domain] = true
		return
	if phase == 3:
		if candidate_index >= candidate_ids.size(): phase = 4; return
		var id: int = candidate_ids[candidate_index]
		candidate_index += 1
		if not towns.has(id): candidates.erase(id)
		return
	if phase == 4:
		if outfit_index >= outfit_ids.size(): finished = true; return
		var id: int = outfit_ids[outfit_index]
		outfit_index += 1
		if not world.person_index.has(id): outfits.erase(id)
		return
	if town_index >= world.towns.size(): phase = 3; return
	var home: Dictionary = world.towns[town_index]
	town_index += 1
	var weights: Dictionary = scores.get(home.id, {}).duplicate()
	var society: Dictionary = world.society_index.get(home.id, {})
	for key in society.get("tech", {}):
		var state: Dictionary = society.tech[key]
		if not state.mastered or int(state.used) == 0: continue
		var domain: String = WorldDevelopment.METHODS[key].domain
		if domain == "science" or domain == "organization": domain = "education"
		if COLORS.has(domain): weights[domain] = float(weights.get(domain, 0.0)) + (2.0 if state.operating else 0.5)
	var focus := "mixed"
	var second := "mixed"
	var best := 0.0
	var runner := 0.0
	var total := 0.0
	for domain in weights:
		var score := float(weights[domain])
		total += score
		if int(counts.get(home.id, {}).get(domain, 0)) == 0 or not activity.get(home.id, {}).has(domain): continue
		if score > best: second = focus; runner = best; focus = domain; best = score
		elif score > runner: second = domain; runner = score
	if int(residents.get(home.id, 0)) < 6 or best < 5.0: focus = "mixed"; second = "mixed"
	elif runner < best * 0.65: second = "mixed"
	var rotation: Dictionary = society.get("tech", {}).get("rotation", {})
	var goods: Dictionary = world.civilization.get(home.id, {}).get("stock", {})
	var style := {"focus": focus, "secondary": second, "share": best / maxf(total, 1.0), "buildings": counts.get(home.id, {}), "rotation": rotation.get("mastered", false) and int(rotation.get("used", 0)) > 0, "food": int(home.food) >= WorldEconomy.LOAD, "stone": int(goods.get("stone", 0)) > 0, "wood": int(home.wood) >= WorldEconomy.LOAD}
	var biome := WorldClimate.biome(world, Vector2i(home.x, home.y))
	style.form = 1 if biome >= 3 else (2 if biome == 1 else posmod(hash(Vector2i(world.world_seed, home.id)), 3))
	var previous: Dictionary = previous_styles.get(home.id, {})
	if previous.is_empty() or (previous.focus == focus and previous.secondary == second):
		candidates.erase(home.id)
	else:
		var signature := focus + ":" + second
		var candidate: Dictionary = candidates.get(home.id, {})
		if candidate.get("signature", "") != signature:
			candidate = {"signature": signature, "since": world.ticks}
			candidates[int(home.id)] = candidate
		if world.ticks - int(candidate.since) < WorldEconomy.DAY_TICKS * 2:
			style.focus = previous.focus; style.secondary = previous.secondary
	towns[int(home.id)] = style
