extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func add_home(world: WorldState, name_value: String, center: Vector2i, jobs: Array, buildings: Array) -> Dictionary:
	world.paint(center, 20, WorldState.Terrain.GRASS)
	var home := {"id": world.next_id, "name": name_value, "x": center.x, "y": center.y, "food": 64, "wood": 32, "level": 2}
	world.next_id += 1; world.towns.append(home)
	WorldSociety.ensure_town(world, home)
	WorldCivilization.ensure(world, home)
	for i in jobs.size():
		world.add_person(center + Vector2i(i - 3, 3), false)
		var member: Dictionary = world.people.back()
		member.home = home.id; member.job = jobs[i]
		member.born_tick = -WorldLife.YEAR * 25
	for i in buildings.size(): WorldEconomy.add_building(world, home, buildings[i], center + Vector2i(i * 4 - 6, -5), true)
	return home

func settle(view: WorldView) -> void:
	for i in 80:
		view._process(0.016)
		if view.appearance_job == null and not view.appearance_dirty: return
	check(false, "appearance cache completes in bounded frames")

func run() -> void:
	var world := WorldState.new()
	var farms := add_home(world, "Луговые поля", Vector2i(-24, 0), ["farmer", "farmer", "farmer", "farmer", "farmer", "forager"], ["farm", "farm", "house", "store"])
	var sea := add_home(world, "Парусный берег", Vector2i(24, 0), ["fisher", "fisher", "sailor", "sailor", "sailor", "merchant"], ["dock", "port", "house"])
	var mixed := add_home(world, "Перекрёсток", Vector2i(0, 28), ["farmer", "farmer", "farmer", "sailor", "sailor", "sailor"], ["farm", "farm", "dock", "port"])
	var identity := WorldAppearanceJob.new(world)
	identity.advance(0)
	check(identity.towns[farms.id].focus == "food", "real farms and farmers identify agricultural settlement")
	check(identity.towns[sea.id].focus == "maritime", "docks and seafarers identify maritime settlement")
	check(identity.towns[mixed.id].secondary != "mixed", "two comparable occupations retain a mixed identity")
	var previous: Dictionary = identity.towns
	var pending := {}
	for member in world.people:
		if member.home == farms.id: member.job = "settler"
	identity = WorldAppearanceJob.new(world); identity.advance(0)
	check(identity.towns[farms.id].focus == "mixed", "unused fields alone do not turn idle residents into a farming civilization")
	identity = WorldAppearanceJob.new(world, {}, previous, pending); identity.advance(0)
	check(identity.towns[farms.id].focus == "food", "brief loss of activity retains the established settlement appearance")
	world.ticks = WorldEconomy.DAY_TICKS * 2 - 1
	identity = WorldAppearanceJob.new(world, {}, previous, pending); identity.advance(0)
	check(identity.towns[farms.id].focus == "food", "appearance remains stable until the observation period ends")
	world.ticks += 1
	identity = WorldAppearanceJob.new(world, {}, previous, pending); identity.advance(0)
	check(identity.towns[farms.id].focus == "mixed", "sustained economic change replaces the appearance without locking a civilization type")
	world.ticks = 0
	for member in world.people:
		if member.home == farms.id: member.job = "farmer"
	var outfits := {999999: {"job": "builder"}}
	identity = WorldAppearanceJob.new(world, outfits); identity.advance(0)
	check(outfits.is_empty(), "dead resident outfits are retired instead of accumulating across generations")
	var saved := JSON.stringify(world.to_dict())
	var view := WorldView.new(); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	view.set_process(false); view.set_world(world); view.zoom = 3.0; view.go_to_cell(Vector2i.ZERO, false)
	settle(view)
	check(JSON.stringify(world.to_dict()) == saved, "visual identity does not spend resources, invent technology or mutate simulation")
	var rebuilds := view.appearance_builds
	for i in 20: view.offset.x += 1; view._process(0.016)
	check(view.appearance_builds == rebuilds, "camera movement reuses settlement profiles")
	var member: Dictionary = world.people[0]
	var original := view._person_outfit(member, 3)
	member.job = "settler"
	check(view._person_outfit(member, 3) == original, "returning from work does not flicker into a generic outfit")
	member.job = "builder"
	check(view._person_outfit(member, 3) == original, "brief task changes retain the established outfit")
	world.ticks += 3
	check(view._person_outfit(member, 3) == view.atlas_jobs.builder, "sustained new work changes the outfit")
	member.skills.build = 120
	check(view._person_outfit(member, 3) == view.atlas_jobs["builder:master"], "personal skill threshold adds the master variant")
	view.visual_season = 3; world.climate.seasons = true
	check(view._person_outfit(member, 3) == view.atlas_jobs["builder:master:cold"], "winter clothing preserves profession and mastery")
	check(view._person_outfit(member, 0) == view.atlas_jobs["child:cold"], "children have no adult tools or mastery badges")
	var forge := WorldEconomy.add_building(world, sea, "forge", Vector2i(35, 0), true)
	member.task = {"kind": "manufacture", "building": forge.id, "work": 1}
	identity = WorldAppearanceJob.new(world); identity.advance(0)
	check(identity.working.has(forge.id), "furnace activity comes from actual manufacturing work")
	member.task = {}; identity = WorldAppearanceJob.new(world); identity.advance(0)
	check(not identity.working.has(forge.id), "unused furnace is displayed without permanent fire")
	check(PixelArt.building_texture("loom").get_image().get_data() != PixelArt.building_texture("workshop").get_image().get_data(), "loom has its own silhouette")
	check(PixelArt.building_texture("port").get_height() > PixelArt.building_texture("dock").get_height(), "port has storage and lifting structure beyond a dock")
	view.set_world(WorldState.new()); settle(view)
	check(view.town_appearances.is_empty() and view.person_outfits.is_empty(), "replacing the world clears old visual identities")
	view.queue_free(); await process_frame
	print("Appearance: %d failures" % failures)
	quit(1 if failures else 0)
