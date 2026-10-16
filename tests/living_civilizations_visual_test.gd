extends "res://tests/living_civilizations_test.gd"

var game

func frame_ready() -> void:
	for i in 60: await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var world := WorldState.new()
	var a := home(world,Vector2i.ZERO,24)
	for i in 72:
		world.add_person(Vector2i(i%13-6,i/13-3),false)
		var member: Dictionary = world.people.back()
		member.home = a.id; member.birth_tick = -25*WorldLife.YEAR; member.sex = "male"
	for i in world.people.size():
		world.people[i].x = (i%13)-6; world.people[i].y = (i/13)-3
	world.population_dirty = true
	a.name = "Каменная гавань"
	for row in [["townhouse",Vector2i(-12,0)],["apartment",Vector2i(-8,-12)],["tower",Vector2i(-12,8)],["tower",Vector2i(-7,8)],["factory",Vector2i(8,-12)],["power",Vector2i(12,-4)],["mill",Vector2i(8,7)],["plaza",Vector2i(-3,5)],["irrigation",Vector2i(4,-3)],["embankment",Vector2i(-12,-12)]]: add_ready(world,a,row[0],row[1])
	for member in world.people: member.skills.build = 220
	for key in WorldSociety.TECH: master(world,a,key)
	var b := home(world,Vector2i(56,0),6)
	b.name = "Дальний берег"
	world.networks.ancestry(world,b,a)
	var link := world.networks.relation(a.id,b.id)
	link.deliveries = 3; link.trust = 78; link.cargo = 18; link.kind = "wood"; link.reason = "Древесина в обмен на камень"
	stock(world,b,"wood",0); stock(world,b,"stone",24)
	world.ticks = WorldEconomy.DAY_TICKS
	var monthly := WorldNetworksJob.new(world)
	while not monthly.finished: monthly.unit()
	WorldLife.reconcile(world)
	check(world.networks.town_index[a.id].stage==5,"metropolis title follows actual population, towers and power")
	var file := FileAccess.open("res://artifacts/living-civilizations-world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(world.to_dict())); file.close()
	check(copy(world)!=null and WorldAudit.conserved(world),"visual city fixture is a valid conservative saved world")
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.paused = true; game.preferences.autosave = false
	game._set_world(world); game.status_panel.hide()
	game.view.zoom = 2.8; game.view.go_to_cell(Vector2i.ZERO,false)
	game._set_drawer("info",false,false)
	await frame_ready()
	root.get_texture().get_image().save_png("res://artifacts/living-city-desktop.png")
	game._inspect(Vector2i.ZERO); game._set_drawer("info",true,false)
	game.inspector.set_expanded("civic",true); game.inspector.set_expanded("network",true)
	var before := JSON.stringify(world.to_dict())
	game._refresh_inspector()
	check(game.inspector.readable_text().contains("Мегаполис") and game.inspector.readable_text().contains("Дальний берег"),"inspector exposes actual city stage and known neighbor")
	check(before==JSON.stringify(world.to_dict()),"new city and relation details never mutate simulation")
	for screen in [[Vector2i(2160,1080),2.25],[Vector2i(1080,2400),3.0]]:
		root.size = screen[0]; game.touch_ui = true; game.inspector.touch_ui = true
		game.system_ui_scale = screen[1]; game.preferences.ui_scale = 1.0
		game._apply_ui_scale(); game._build_theme(); game._prepare_touch_ui(game); game._responsive()
		game.view.zoom = 2.0; game.view.go_to_cell(Vector2i(-6,0),false)
		game.selected_cell = WorldState.NO_CELL; game.inspected_person_id = -1
		game._inspect(Vector2i.ZERO); game.inspector.set_expanded("civic",true); game._refresh_inspector()
		game.history_scroll.scroll_vertical = 260
		await frame_ready()
		check(game.inspector.selection_kind=="town","phone fixture inspects the settlement rather than cycling to a resident")
		check(Rect2(Vector2.ZERO,game.size).encloses(game.sidebar.get_global_rect()),"city inspector fits phone viewport")
		check(game.inspector.sections.civic.button.custom_minimum_size.y*game.ui_scale/game.system_ui_scale>=47.9,"new section keeps a 48 dp target")
		check(game.history_scroll.get_h_scroll_bar().max_value<=game.history_scroll.size.x+1,"new details do not overflow horizontally")
		root.get_texture().get_image().save_png("res://artifacts/living-city-%dx%d.png" % [screen[0].x,screen[0].y])
		game.inspector.set_expanded("civic",false); game.inspector.set_expanded("network",true); game._refresh_inspector()
		await frame_ready()
		root.get_texture().get_image().save_png("res://artifacts/living-relations-%dx%d.png" % [screen[0].x,screen[0].y])
	game.queue_free(); await process_frame
	print("Living civilization visuals: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
