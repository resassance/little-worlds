extends "res://tests/appearance_test.gd"

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func traffic(world: WorldState, first: Vector2i, last: Vector2i) -> void:
	var member := {"id":1,"x":first.x,"y":first.y}
	var point := first
	while point != last:
		var next := point+Vector2i(signi(last.x-point.x),0) if point.x != last.x else point+Vector2i(0,signi(last.y-point.y))
		member.x = next.x; member.y = next.y; world.landscape.moved(world,member,point); point = next

func run() -> void:
	root.size = Vector2i(1280,800)
	var world := WorldState.new()
	var home := add_home(world,"Город у старого леса",Vector2i.ZERO,["builder","farmer","miner","merchant","logger","forager"],["house","farm","market","workshop"])
	world.paint(Vector2i(-13,0),8,WorldState.Terrain.FOREST)
	world.paint(Vector2i(13,-7),4,WorldState.Terrain.MOUNTAIN)
	var view := WorldView.new(); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	view.set_world(world); view.zoom = 2.6; view.go_to_cell(Vector2i.ZERO,false)
	view.interface_visible = false
	for i in 100: await frame()
	root.get_texture().get_image().save_png("res://artifacts/landscape-before.png")
	world.ticks = 3
	for repeat in 16:
		for value in world.buildings:
			traffic(world,Vector2i.ZERO,Vector2i(value.x,value.y))
			if value.kind == "farm": value.planted = true; value.growth = 45
		traffic(world,Vector2i.ZERO,Vector2i(-12,1)); traffic(world,Vector2i.ZERO,Vector2i(10,-7)); world.ticks += 4
	for cell in [Vector2i(-12,1),Vector2i(-10,2),Vector2i(-14,-2),Vector2i(-11,-1)]: world.harvest_wood(cell,12)
	world.mineral_deposits[Vector2i(11,-7)] = 0; world.landscape.site(Vector2i(11,-7),"quarry")
	world.landscape.scar(world,Vector2i(7,7),"ruin",2)
	world.landscape.scar(world,Vector2i(-7,-7),"burn")
	world.terrain_changed.emit(); world.changed.emit()
	var model := JSON.stringify(world.to_dict())
	for i in 120: await frame()
	root.get_texture().get_image().save_png("res://artifacts/landscape-after.png")
	check(not view.landscape_textures.is_empty() and view.landscape_textures.size() <= 32,"living ground uses a bounded texture cache")
	check(JSON.stringify(world.to_dict()) == model,"rendering leaves the saved history unchanged")
	view.zoom = 0.15
	for i in 20: await frame()
	check(view.landscape_textures.size() <= 32,"zooming out does not create an unbounded ground cache")
	view.set_world(WorldState.new())
	check(view.landscape_textures.is_empty() and view.landscape_queue.is_empty(),"world switch clears ground textures and requests")
	view.queue_free(); await process_frame
	print("Landscape rendering: ",failures," failures")
	quit(1 if failures else 0)
