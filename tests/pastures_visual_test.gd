extends "res://tests/pastures_test.gd"

var game

func wait_view() -> void:
	for i in 50: await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var world := WorldState.new()
	var settlement := home(world,Vector2i.ZERO,12)
	settlement.name = "Овечий брод"
	for key in ["husbandry","weaving"]: master(world,settlement,key)
	add_ready(world,settlement,"pasture",Vector2i(-11,-1))
	add_ready(world,settlement,"loom",Vector2i(-12,-7))
	world.fauna.add(world,"sheep",Vector2i(-10,0),6,settlement.id)
	world.fauna.add(world,"goat",Vector2i(-5,7),3,settlement.id)
	world.fauna.add(world,"deer",Vector2i(11,5),4)
	for i in 6:
		WorldCulture.record(world,settlement,"pastoral",32)
		world.ticks += WorldEconomy.DAY_TICKS; WorldCulture.monthly(world,settlement)
	stock(world,settlement,"wool",6)
	var member: Dictionary = world.people[0]
	world.fauna.assign(world,member,settlement,true)
	WorldEconomy.execute(world,member,settlement)
	check(copy(world)!=null and WorldAudit.conserved(world),"prepared pastoral fixture has valid inventory and animal care")
	var file := FileAccess.open("res://artifacts/pastures-world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(world.to_dict())); file.close()
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.paused = true; game.preferences.autosave = false; game._set_world(world); game.status_panel.hide(); game.view.reduce_motion = true
	for screen in [[Vector2i(1440,900),1.0],[Vector2i(2160,1080),2.25],[Vector2i(1080,2400),3.0]]:
		root.size = screen[0]; game.touch_ui = screen[1]>1; game.inspector.touch_ui = game.touch_ui
		game.system_ui_scale = screen[1]; game.preferences.ui_scale = 1
		game._apply_ui_scale(); game._build_theme()
		if game.touch_ui: game._prepare_touch_ui(game)
		game._responsive(); game.view.zoom = 2.5; game.view.go_to_cell(Vector2i(-7,0),false)
		game.selected_cell = WorldState.NO_CELL; game.inspected_person_id = -1
		game._inspect(Vector2i.ZERO); game._set_drawer("info",true,false)
		game.inspector.set_expanded("culture",true); game.inspector.set_expanded("fauna",true)
		var before := JSON.stringify(world.to_dict()); game._refresh_inspector()
		await wait_view()
		game.history_scroll.ensure_control_visible(game.inspector.sections.culture.body)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		check(game.inspector.readable_text().contains("Община скотоводов") and game.inspector.readable_text().contains("Овцы"),"inspector shows tradition and actual herds")
		check(before==JSON.stringify(world.to_dict()),"animal and culture details do not change the simulation")
		check(game.view.fauna_mesh.visible_instance_count>0,"visible animals are uploaded to their shared mesh")
		check(Rect2(Vector2.ZERO,game.size).encloses(game.sidebar.get_global_rect()),"pastoral inspector fits the screen")
		check(game.history_scroll.get_h_scroll_bar().max_value<=game.history_scroll.size.x+1,"new details fit without horizontal scroll")
		if screen[1]==1.0:
			var shown := hash(root.get_texture().get_image().get_data())
			game.view.fauna_layer.hide()
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			check(shown!=hash(root.get_texture().get_image().get_data()),"animal batch changes actual rendered pixels")
			game.view.fauna_layer.show()
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/pastures-%dx%d.png" % [screen[0].x,screen[0].y])
		game.history_scroll.ensure_control_visible(game.inspector.sections.fauna.body)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/herds-%dx%d.png" % [screen[0].x,screen[0].y])
		game.inspector.set_expanded("culture",false); game.inspector.set_expanded("fauna",false)
	game._set_drawer("info",false,false)
	root.size = Vector2i(1440,900); game.system_ui_scale = 1.0; game.preferences.ui_scale = 1.0; game._apply_ui_scale(); game._responsive()
	game.view.zoom = 2.6; game.view.go_to_cell(Vector2i.ZERO,false); await wait_view()
	root.get_texture().get_image().save_png("res://artifacts/pastures-overview.png")
	game.view.zoom = 0.2; await wait_view()
	check(game.view.fauna_mesh.visible_instance_count==0,"far zoom skips animal sprites")
	game.view.zoom = 2.5; await wait_view()
	check(game.view.fauna_mesh.visible_instance_count>0,"animals reappear after zooming back in")
	game.inspector.present(world,Vector2i(-9,0),{},{},{})
	check(game.inspector.selection_kind=="herd" and game.inspector.title_label.text=="Овцы","a herd can be inspected directly on the map")
	game.queue_free(); await process_frame
	print("Pasture visuals: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
