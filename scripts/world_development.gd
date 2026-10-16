class_name WorldDevelopment
extends RefCounted

const PRACTICE_DOMAINS := {"food":"food","farm":"food","wood":"engineering","build":"engineering"}

const RANDOM_MODULUS := 2147483647
static var catalog: Dictionary = load_catalog()
static var DOMAINS: Dictionary = catalog.domains
static var METHODS: Dictionary = catalog.methods
static var CONSTRUCTION: Dictionary = catalog.construction

static func load_catalog() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/development.json"))
	assert(source is Dictionary and source.get("domains") is Dictionary and source.get("methods") is Dictionary and source.get("construction") is Dictionary, "Invalid development catalog")
	for key in source.methods:
		var spec: Dictionary = source.methods[key]
		assert(source.domains.has(spec.domain) and spec.work >= 4 and spec.work == floor(spec.work), "Invalid method definition")
		spec.work = int(spec.work)
		for field in ["practice", "experts", "inputs"]:
			for requirement in spec[field]:
				var amount: float = spec[field][requirement]
				assert(amount > 0 and amount == floor(amount), "Invalid method requirement")
				spec[field][requirement] = int(amount)
		for feature in spec.weights: assert(is_finite(float(spec.weights[feature])), "Invalid method weight")
	for kind in source.construction:
		for skill in source.construction[kind]: source.construction[kind][skill] = int(source.construction[kind][skill])
	return source

static func seed_for(world, town: int, stream: String) -> int:
	return 1 + posmod(hash("%d:%d:development:%s" % [world.world_seed, town, stream]), RANDOM_MODULUS - 1)

static func draw(holder: Dictionary, field: String) -> float:
	holder[field] = (int(holder[field]) * 48271) % RANDOM_MODULUS
	return float(holder[field]) / RANDOM_MODULUS

static func initialize(world, society: Dictionary) -> void:
	society.choice_rng = seed_for(world, society.town, "choice")
	society.project_reason = ""
	society.domain_practice = {}
	for domain in DOMAINS: society.domain_practice[domain] = 0
	for key in METHODS: initialize_method(world,society,key)

static func initialize_method(world, society: Dictionary, key: String) -> void:
	var state: Dictionary = society.tech[key]
	state.experiment_rng = seed_for(world, society.town, key)
	state.threshold = 0.0
	state.intensity = 0.0
	state.attempts = 0
	state.attempt_work = 0
	state.work_done = int(state.progress)
	state.retry_tick = 0
	state.spent = false

static func practice(society: Dictionary, member: Dictionary, skill: String) -> void:
	var domain: String = PRACTICE_DOMAINS[skill]
	if member.task.get("kind", "") == "fish": domain = "maritime"
	elif member.task.get("kind", "") == "research": domain = METHODS[member.task.tech].domain
	elif member.task.get("kind", "") == "manufacture": domain = "materials"
	society.domain_practice[domain] = mini(WorldSociety.LIMIT, int(society.domain_practice[domain]) + 1)

static func profile(world, home: Dictionary) -> Dictionary:
	var society := WorldSociety.get_society(world, home.id)
	var result := {}
	for domain in DOMAINS:
		result[domain] = {"known": 0, "mastered": 0, "operating": 0, "used": 0, "practice": int(society.domain_practice[domain])}
	for key in METHODS:
		var value: Dictionary = result[METHODS[key].domain]
		var state: Dictionary = society.tech[key]
		value.known += int(state.known)
		value.mastered += int(state.mastered)
		value.operating += int(WorldSociety.active(world, home, key))
		value.used += int(state.used)
	return result

static func construction_ready(world, home: Dictionary, kind: String) -> bool:
	if not world.networks.construction_ready(world,home,kind): return false
	var available := WorldSociety.experts(world, home)
	for skill in CONSTRUCTION.get(kind, {}):
		if int(available[skill]) < int(CONSTRUCTION[kind][skill]): return false
	if kind == "school" and WorldSociety.get_society(world, home.id).taught == 0: return false
	return true

static func context(world, home: Dictionary) -> Dictionary:
	var nav := WorldEconomy.navigation(world, home)
	var residents := WorldEconomy.members(world, home)
	var curiosity := 0.0
	var teachers := 0
	for member in residents:
		if not WorldLife.adult(world, member) or WorldTravel.away(world, member.id): continue
		if not nav.parents.has(Vector2i(member.x, member.y)): continue
		curiosity += float(member.traits.curiosity) / 2.0
		if member.traits.curiosity > 0 and int(member.skills.build) >= 40: teachers += 1
	var contacts := 0
	for value in world.contacts:
		if home.id in [value.a, value.b]: contacts += 1
	return {"livestock":clampf(float(world.fauna.owned(home))/6.0,0,1), "grassland":clampf(float(nav.food.size())/160.0,0,1), "coast": clampf(float(nav.coasts.size()) / 64.0, 0, 1), "forest": clampf(float(nav.wood.size()) / 80.0, 0, 1), "minerals": clampf(float(nav.quarries.size()) / 12.0, 0, 1), "farms": clampf(float(WorldEconomy.count(world, home, "farm")) / 2.0, 0, 1), "food_pressure": clampf(1.0 - WorldEconomy.food_days(world, home) / 30.0, 0, 1), "wood_pressure": clampf(1.0 - float(home.wood) / 32.0, 0, 1), "teachers": clampf(float(teachers) / 3.0, 0, 1), "contacts": clampf(float(contacts) / 3.0, 0, 1), "population": clampf(float(residents.size()) / 24.0, 0, 1), "curiosity": curiosity / maxi(1, residents.size()), "cold": float(WorldClimate.biome(world, Vector2i(home.x, home.y)) >= 4 or (world.climate.seasons and WorldClimate.season(world) == 3))}

static func candidates(world, home: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var society := WorldSociety.get_society(world, home.id)
	if WorldEconomy.food_days(world, home) < 6: return result
	var local := context(world, home)
	var available := WorldSociety.experts(world, home)
	for key in METHODS:
		var state: Dictionary = society.tech[key]
		if not state.known or state.mastered or int(state.retry_tick) > world.ticks or not WorldSociety.reason(world, home, key).is_empty(): continue
		var spec: Dictionary = METHODS[key]
		var utility := 0.35 * float(available[spec.skill]) / WorldSocial.MAX_XP + 0.25 * float(local.curiosity)
		var strongest := 0.0
		var cause := "есть специалист и материалы для опытов"
		for feature in spec.weights:
			var contribution: float = float(spec.weights[feature]) * float(local[feature])
			utility += contribution
			if contribution > strongest:
				strongest = contribution
				cause = {"livestock":"приручённое стадо даёт практику ухода за животными", "grassland":"доступны пастбища", "coast": "доступен берег для морского дела", "forest": "местные леса дают работу плотникам", "minerals": "доступны местные залежи", "farms": "поля дают опыт земледелия", "food_pressure": "нужно надёжнее снабжать жителей едой", "wood_pressure": "нужно экономнее расходовать древесину", "teachers": "есть мастера для передачи знаний", "contacts": "контакты открывают новые задачи", "population": "растущей общине нужна организация", "cold": "холод требует тёплой одежды"}[feature]
		utility += 0.2 * clampf(float(society.domain_practice[spec.domain]) / 200.0, 0, 1)
		utility -= mini(3, int(state.attempts)) * 0.2
		result.append({"key": key, "weight": exp(clampf(utility / 0.85, -6, 6)), "reason": cause})
	return result

static func choose(world, home: Dictionary, society: Dictionary) -> void:
	var options := candidates(world, home)
	if options.is_empty(): return
	var total := 0.0
	for option in options: total += float(option.weight)
	var position := draw(society, "choice_rng") * total
	var selected: Dictionary = options.back()
	for option in options:
		position -= float(option.weight)
		if position < 0:
			selected = option
			break
	society.project = selected.key
	society.project_reason = selected.reason

static func experiment(world, home: Dictionary, society: Dictionary, key: String, member: Dictionary) -> bool:
	var state: Dictionary = society.tech[key]
	var spec: Dictionary = METHODS[key]
	if not state.spent:
		if not WorldCivilization.inputs_available(world, home, spec.inputs): return false
		WorldCivilization.consume(world, home, spec.inputs)
		state.spent = true
	if state.threshold == 0.0:
		state.threshold = -log(1.0 - draw(state, "experiment_rng"))
		state.attempts = mini(WorldSociety.LIMIT, int(state.attempts) + 1)
	state.attempt_work += 1
	state.work_done = mini(WorldSociety.LIMIT, int(state.work_done) + 1)
	society.domain_practice.science = mini(WorldSociety.LIMIT, int(society.domain_practice.science) + 1)
	state.progress = mini(int(spec.work), int(state.progress) + 1)
	if state.attempt_work > int(spec.work) / 4:
		var quality := 0.75 + 0.5 * float(member.skills[spec.skill]) / WorldSocial.MAX_XP + 0.15 * float(member.traits.curiosity)
		state.intensity += quality / (float(spec.work) * 0.6)
	if state.intensity >= state.threshold: return true
	if state.attempt_work >= int(spec.work) * 2:
		WorldEconomy.set_task(world, member, {})
		society.project = ""
		society.project_reason = ""
		state.retry_tick = world.ticks + WorldEconomy.DAY_TICKS * 2
		state.threshold = 0.0
		state.intensity = 0.0
		state.attempt_work = 0
		state.spent = false
		world.log_event("Опыт не удался", "%s: %s. Материалы израсходованы; община отложила новую попытку." % [home.name, spec.name])
	return false

static func valid_number(value: Variant, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= maximum

static func restore(society: Dictionary, version: int, world) -> bool:
	if version < 10:
		initialize(world, society)
		for key in METHODS:
			var state: Dictionary = society.tech[key]
			if not state.mastered and state.progress > 0:
				state.attempt_work = int(state.progress)
				state.threshold = -log(1.0 - draw(state, "experiment_rng"))
				state.attempts = 1
				state.intensity = maxf(0, float(state.progress) - float(METHODS[key].work) / 4.0) / (float(METHODS[key].work) * 0.6)
		return true
	if not WorldState._integer(society.get("choice_rng")) or society.choice_rng <= 0 or society.choice_rng >= RANDOM_MODULUS: return false
	society.choice_rng = int(society.choice_rng)
	if not society.get("project_reason") is String or society.project_reason.length() > 160: return false
	if not society.get("domain_practice") is Dictionary or society.domain_practice.size() != DOMAINS.size(): return false
	for domain in DOMAINS:
		if not WorldState._integer(society.domain_practice.get(domain)) or society.domain_practice[domain] < 0 or society.domain_practice[domain] > WorldSociety.LIMIT: return false
		society.domain_practice[domain] = int(society.domain_practice[domain])
	for key in METHODS:
		var state: Dictionary = society.tech[key]
		for field in ["experiment_rng", "attempts", "attempt_work", "work_done", "retry_tick"]:
			if not WorldState._integer(state.get(field)): return false
			state[field] = int(state[field])
		if state.experiment_rng <= 0 or state.experiment_rng >= RANDOM_MODULUS or state.attempts < 0 or state.attempts > WorldSociety.LIMIT: return false
		if state.work_done < 0 or state.work_done > WorldSociety.LIMIT: return false
		if state.attempt_work < 0 or state.attempt_work > int(METHODS[key].work) * 2 or state.retry_tick < 0 or state.retry_tick > world.ticks + WorldEconomy.DAY_TICKS * 2: return false
		if not valid_number(state.get("threshold"), 24) or not valid_number(state.get("intensity"), 10) or not state.get("spent") is bool: return false
		if state.threshold == 0 and (state.intensity > 0 or state.attempt_work > 0): return false
		if state.threshold > 0 and state.attempts == 0: return false
		if state.attempt_work > state.work_done: return false
		if not state.known and (state.attempts > 0 or state.work_done > 0 or state.spent or state.retry_tick > 0): return false
		if state.retry_tick > world.ticks and (state.threshold > 0 or state.spent or state.attempt_work > 0): return false
		if state.mastered and state.threshold > 0 and state.intensity < state.threshold: return false
		state.threshold = float(state.threshold)
		state.intensity = float(state.intensity)
	return true
