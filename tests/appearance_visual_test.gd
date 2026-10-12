extends "res://tests/appearance_test.gd"

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(1440, 900)
	var world := WorldState.new()
	var specs := [
		["Луговые поля", Vector2i(-26, -15), ["farmer", "farmer", "farmer", "farmer", "farmer", "forager"], ["farm", "farm", "house", "store"]],
		["Парусный берег", Vector2i(0, -15), ["fisher", "fisher", "sailor", "sailor", "sailor", "merchant"], ["dock", "port", "house", "store"]],
		["Двор мастеров", Vector2i(26, -15), ["builder", "builder", "logger", "logger", "builder", "builder"], ["workshop", "workshop", "house", "store"]],
		["Красная печь", Vector2i(-26, 15), ["miner", "artisan", "artisan", "miner", "artisan", "artisan"], ["kiln", "forge", "loom", "house"]],
		["Тихий архив", Vector2i(0, 15), ["teacher", "teacher", "researcher", "researcher", "teacher", "researcher"], ["school", "archive", "house", "store"]],
		["Путь купцов", Vector2i(26, 15), ["merchant", "merchant", "merchant", "merchant", "merchant", "merchant"], ["market", "market", "house", "store"]]
	]
	for spec in specs:
		var home := add_home(world, spec[0], spec[1], spec[2], spec[3])
		world.civilization[home.id].stock.stone = 8
		for i in 6:
			var member: Dictionary = world.people[world.people.size() - 6 + i]
			member.x = int(spec[1].x) - 8 + i * 3
			member.y = int(spec[1].y) + 5
			if i % 2 == 0:
				for skill in member.skills: member.skills[skill] = 120
	var view := WorldView.new(); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	view.set_world(world); view.zoom = 1.6; view.go_to_cell(Vector2i.ZERO, false)
	for i in 90: await frame()
	check(view.town_appearances.size() == 6, "six visible settlement profiles are prepared")
	check(view.people_multimesh.visible_instance_count == 36, "professions share one instanced mesh")
	root.get_texture().get_image().save_png("res://artifacts/appearance-settlements.png")
	var state := JSON.stringify(world.to_dict())
	view.zoom = 4.0; view.go_to_cell(Vector2i(-24, 19), false)
	for i in 8: await frame()
	root.get_texture().get_image().save_png("res://artifacts/appearance-professions.png")
	view.zoom = 1.6; view.go_to_cell(Vector2i.ZERO, false)
	world.climate.seasons = true; world.ticks = WorldLife.YEAR * 3 / 4
	for i in 8: await frame()
	root.get_texture().get_image().save_png("res://artifacts/appearance-winter.png")
	view.zoom = 0.1
	await frame(); await frame()
	check(view.people_multimesh.visible_instance_count == 0, "overview hides profession detail")
	check(view.people_atlas.get_width() <= 2048, "profession atlas fits conservative mobile texture limits")
	world.climate.seasons = false; world.ticks = 0
	check(JSON.stringify(world.to_dict()) == state, "camera, clothing and atlas rendering leave the simulated world unchanged")
	view.queue_free(); await process_frame
	print("Appearance rendering: %d failures" % failures)
	quit(1 if failures else 0)
