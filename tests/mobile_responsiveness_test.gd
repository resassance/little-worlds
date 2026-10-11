extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false); game.view.set_process(false)
	game.preferences.autosave = false
	var world := WorldState.new()
	world.generate(42817)
	var land: Array[Vector2i] = []
	for y in world.height:
		for x in world.width:
			if world.walkable(Vector2i(x,y)): land.append(Vector2i(x,y))
	for i in 2000: world.add_person(land[(i*13)%land.size()],false)
	for i in 21: world.step()
	game._set_world(world)
	game._set_speed(5); game.paused = false
	var cell := Vector2i(world.towns[0].x,world.towns[0].y)
	var before := world.ticks
	var maximum := 0
	var durations: Array[int] = []
	for i in 500:
		if i % 100 == 0:
			var start := Time.get_ticks_usec()
			game._request_inspection(cell)
			check(Time.get_ticks_usec()-start < 16000, "inspection tap returns immediately under load")
		var start := Time.get_ticks_usec()
		game._process(.016)
		var elapsed := Time.get_ticks_usec()-start
		durations.append(elapsed); maximum = maxi(maximum,elapsed)
	check(world.ticks > before, "2000 residents advance at x5")
	check(game.inspector_updates >= 2, "inspector updates between ticks under sustained load")
	check(game.pending_actions.is_empty(), "inspection requests are processed")
	check(game.accumulator <= .4, "overload keeps bounded time debt")
	game.paused = true
	game._finish_work()
	check(not world.stepping, "pause finishes the current tick")
	check(WorldAudit.conserved(world), "frame scheduling and inspection conserve resources")
	var updates: int = game.inspector_updates
	game._set_drawer("info",false,false)
	world.step()
	for i in 30: game._process(.016)
	check(game.inspector_updates == updates, "closed inspector remains idle under load")
	game._request_inspection(cell)
	game._set_drawer("info",false,false)
	game._process(.016)
	check(not game.info_open, "closing drawer cancels deferred reopening")
	var occupants := world.population.nearby(world, cell, 0)
	if occupants.is_empty():
		var member: Dictionary = world.people[0]
		var old_cell := Vector2i(member.x, member.y)
		member.x = cell.x; member.y = cell.y
		world.track_person_move(member, old_cell)
		occupants = world.population.nearby(world, cell, 0)
	game.selected_cell = WorldState.NO_CELL; game.inspected_person_id = -1
	game._request_inspection(cell); game._process(.016)
	check(game.inspected_person_id == -1, "first camp tap selects the settlement")
	game._request_inspection(cell); game._process(.016)
	check(game.inspected_person_id == occupants[0].id, "second camp tap selects its first actual occupant")
	for i in occupants.size(): game._request_inspection(cell)
	check(game.pending_actions.is_empty(), "rapid camp taps do not accumulate individual inspector actions")
	game._process(.016)
	check(game.inspected_person_id == -1, "coalesced taps preserve cycling through every occupant and the camp")
	var latest := cell + Vector2i(4, 0)
	for i in 100: game._request_inspection(cell + Vector2i(i % 5, 0))
	game._process(.016)
	check(game.selected_cell == latest and game.pending_inspection == WorldState.NO_CELL, "rapid taps inspect only the latest requested cell")
	durations.sort()
	print("Interactive 2000 residents: %d completed ticks, script p95 %.2f ms, max %.2f ms" % [world.ticks-before,durations[int(durations.size()*.95)]/1000.0,maximum/1000.0])
	print("Mobile responsiveness: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
