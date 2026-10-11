extends SceneTree

var game: Control
var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in 8: await process_frame
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(1920,1080)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused = true
	game.preferences.autosave = false
	check(game.touch_ui, "touch interface enabled")
	game.preferences.ui_scale = 1.0
	for screen in [[Vector2i(1920,1080),3.0],[Vector2i(2160,1080),2.25],[Vector2i(2340,1080),2.625],[Vector2i(2400,1080),3.0],[Vector2i(1080,2400),3.0],[Vector2i(1180,820),2.0]]:
		var physical: Vector2i = screen[0]
		game.system_ui_scale = screen[1]
		game._apply_ui_scale()
		root.size = physical
		await settle()
		var controls: Array[Control] = [game.world_menu,game.tools_button,game.info_button,game.pause_button,game.speed_button,game.reveal_button]
		for button in controls:
			check(button.size.x >= 48 and button.size.y >= 48, "48 logical pixels touch target: " + button.name)
		check(not game.tools_button.get_global_rect().intersects(game.bottom_controls.get_global_rect()), "bottom dock does not overlap at " + str(physical))
		check(not game.world_menu.get_global_rect().intersects(game.top_time.get_global_rect()), "top controls do not overlap at " + str(physical))
		game._set_drawer("tools",true,false)
		await settle()
		check(Rect2(Vector2.ZERO,game.size).encloses(game.tool_panel.get_global_rect()), "tools drawer fits logical viewport")
		for button in game.tool_buttons.values():
			check(button.size.y >= 48, "tool button remains large")
		game._set_drawer("info",true,false)
		await settle()
		check(not game.tools_open and game.info_open, "one drawer at a time on phone")
		check(Rect2(Vector2.ZERO,game.size).encloses(game.sidebar.get_global_rect()), "inspector fits logical viewport")
		for id in [0,3,4,5,6,10]:
			game._world_menu_selected(id)
			await settle()
			for dialog in [game.generation_dialog,game.settings_dialog,game.navigation_dialog,game.climate_dialog,game.help_dialog,game.sculpt_dialog]:
				if dialog.visible:
					check(dialog.size.x <= game.size.x - 16 and dialog.size.y <= game.size.y - 16, "mobile modal fits: " + dialog.title + " " + str(game.size) + " / " + str(dialog.size))
					check(dialog.get_ok_button().size.y >= 48, "modal action has a large target")
					dialog.hide()
		game._set_drawer("info",false,false)
		await settle()
		root.get_texture().get_image().save_png("res://artifacts/mobile-%dx%d.png" % [physical.x,physical.y])
	game.system_ui_scale = 2.25
	root.size = Vector2i(2160,1080)
	game._apply_ui_scale()
	await settle()
	var normal_scale: float = game.ui_scale
	game._set_ui_scale(0)
	await settle()
	check(game.ui_scale < normal_scale,"compact preference reduces interface scale")
	check(game.tools_button.size.y * game.ui_scale / game.system_ui_scale >= 47.9,"compact option retains a 48 dp touch area")
	game._set_ui_scale(3)
	await settle()
	check(game.ui_scale > normal_scale,"large preference enlarges interface")
	check(not game.tools_button.get_global_rect().intersects(game.bottom_controls.get_global_rect()),"dock fits with enlarged interface")
	game._set_ui_scale(1)
	await settle()
	check(is_equal_approx(game.ui_scale,normal_scale),"system scale can be restored")
	check(game.tools_button.size.x < 120,"mobile brush button releases its previous desktop width")
	var world := WorldState.new()
	world.generate(42817)
	world.populate_demo()
	game._set_world(world)
	game._select_tool("inspect")
	var cell := Vector2i(world.people[0].x,world.people[0].y)
	game.view.go_to_cell(cell)
	var tap := InputEventScreenTouch.new()
	tap.index = 0; tap.position = game.view.cell_to_local(cell)
	for i in 2:
		tap.pressed = true; game.view._gui_input(tap)
		tap.pressed = false; game.view._gui_input(tap)
		await settle()
	check(game.info_open and game.selected_cell == cell, "repeated touch taps select a tile")
	game._set_drawer("info",false,false)
	var updates: int = game.inspector_updates
	for i in 10: world.step()
	await settle()
	check(game.inspector_updates == updates, "hidden inspector does not rebuild on simulation steps")
	game._set_speed(5)
	game.paused = false
	var before := world.ticks
	await create_timer(2.0).timeout
	game.paused = true
	game._finish_work()
	check(world.ticks > before, "x5 simulation runs through frame scheduler")
	check(game.accumulator <= .4, "overload cannot accumulate an unbounded backlog")
	print("Mobile UI: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	for i in 3: await process_frame
	quit(1 if failures else 0)
