class_name WorldConstructionPlanJob
extends RefCounted

var world
var home: Dictionary
var phase := 0
var kind := ""
var options: Array = []
var cursor := 0
var site_job: WorldSiteJob
var finished := false
var industry := false

func _init(value, settlement: Dictionary, industrial: bool = false) -> void:
	world = value; home = settlement; industry = industrial
	if industry: _industry()

func _industry() -> void:
	industry = true
	options = ["dock", "kiln", "loom", "forge", "market", "school", "council", "port"]
	var ship_kind := "sailboat" if WorldSociety.mastered(world, home, "sailing") else "boat"
	if (WorldSociety.mastered(world, home, "navigation") or WorldSociety.mastered(world, home, "sailing")) and WorldEconomy.count(world, home, ship_kind, false) == 0: options.push_front(ship_kind)
	phase = 4

func _later_kind() -> void:
	if WorldEconomy.count(world, home, "store", false) == 0: kind = "store"
	elif WorldLife.needs_home(world, home): kind = "house"
	elif WorldDevelopment.construction_ready(world, home, "workshop") and WorldEconomy.count(world, home, "workshop", false) == 0: kind = "workshop"
	elif WorldDevelopment.construction_ready(world, home, "archive") and WorldEconomy.count(world, home, "archive", false) == 0: kind = "archive"
	else: _industry(); return
	phase = 2

func _build() -> void:
	if site_job.result == WorldState.NO_CELL:
		if industry: cursor += 1; site_job = null; phase = 4
		else: finished = true
		return
	var value := WorldEconomy.add_building(world, home, kind, site_job.result)
	if industry: world.log_event("Начата стройка", "%s: %s. Все материалы доставят жители." % [home.name, WorldEconomy.NAMES[kind]])
	elif not value.is_empty(): world.log_event("Начата стройка", "%s: %s. Материалы доставят жители." % [home.name, WorldEconomy.NAMES[kind].to_lower()])
	finished = true

func unit() -> void:
	if finished: return
	match phase:
		0:
			var residents := WorldEconomy.members(world, home)
			if residents.is_empty(): finished = true; return
			var expand_storage := WorldEconomy.storage_pressure(world, home)
			home.level = 3 if WorldEconomy.count(world, home, "store") > 0 and WorldEconomy.count(world, home, "farm") > 0 else (2 if WorldEconomy.count(world, home, "house") > 0 else 1)
			for value in world.workforce.buildings(world, home):
				if value.town == home.id and not value.ready and (not expand_storage or value.kind == "store"): finished = true; return
			if WorldEconomy.food_days(world, home) < 2 and not expand_storage: finished = true; return
			if expand_storage: kind = "store"; phase = 2
			elif WorldEconomy.housing(world, home) < residents.size() + 1: kind = "house"; phase = 2
			elif WorldEconomy.count(world, home, "farm", false) < maxi(1, ceili(residents.size() / 12.0)):
				site_job = WorldSiteJob.new(world, home, "farm"); phase = 1
			else: _later_kind()
		1:
			if not site_job.finished: site_job.unit(); return
			if site_job.result != WorldState.NO_CELL: kind = "farm"; phase = 2
			else: site_job = null; _later_kind()
		2:
			if WorldEconomy.available_wood(world, home) < int(WorldEconomy.COST[kind]): finished = true; return
			if site_job == null: site_job = WorldSiteJob.new(world, home, kind)
			phase = 3
		3:
			if not site_job.finished: site_job.unit(); return
			_build()
		4:
			if cursor >= options.size(): finished = true; return
			kind = options[cursor]
			if not WorldDevelopment.construction_ready(world, home, kind) or WorldEconomy.count(world, home, kind, false) > 0: cursor += 1; return
			if not WorldCivilization.inputs_available(world, home, WorldCivilization.EXTRA.get(kind, {})) or WorldEconomy.available_wood(world, home) < int(WorldEconomy.COST[kind]): cursor += 1; return
			site_job = WorldSiteJob.new(world, home, kind); phase = 3
