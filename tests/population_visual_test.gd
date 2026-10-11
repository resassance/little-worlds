extends SceneTree
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	call_deferred("run")

func settle() -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	if not game.paused: game._toggle_pause()
	var world := WorldState.new()
	world.generate(42817)
	var land: Array[Vector2i] = []
	for y in world.height:
		for x in world.width:
			if world.walkable(Vector2i(x, y)): land.append(Vector2i(x, y))
	for i in 2000: world.add_person(land[(i * 13) % land.size()], false)
	for i in 21: world.step()
	game._set_world(world)
	game.view.focus_island()
	await settle()
	check(world.people.size() == 2000, "graphical scene accepts all 2000 living people")
	check(not game.view.visible_people.is_empty(), "near camera draws real residents")
	var state := JSON.stringify(world.to_dict())
	game.view.go_to_cell(Vector2i(800000, -800000))
	await settle()
	check(game.view.visible_people.is_empty() and game.view.person_positions.is_empty(), "distant camera does not animate offscreen people")
	check(JSON.stringify(world.to_dict()) == state, "camera culling leaves full simulation state unchanged")
	game.view.focus_island()
	await settle()
	check(not game.view.visible_people.is_empty(), "returning camera restores visible residents")
	game.view.zoom = 0.1
	await settle()
	check(game.view.visible_people.is_empty(), "overview displays settlements without per-person animation")
	game.view.focus_island()
	await settle()
	var victim: Dictionary = game.view.visible_people[0]
	world.remove_person(world.people.find(victim), "визуальная проверка")
	world.add_person(Vector2i(victim.x, victim.y), false)
	await settle()
	var stale := false
	for person in game.view.visible_people:
		if person.id == victim.id: stale = true
	check(world.people.size() == 2000 and not stale, "same-size population replacement invalidates visible identities")
	check(root.get_texture().get_image().save_png("res://artifacts/world-population-2000.png") == OK, "2000-person screenshot saved")
	print("Population visual: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
