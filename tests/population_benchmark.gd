extends SceneTree

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var population := int(arguments[0]) if not arguments.is_empty() else 2000
	if population < 1 or population > WorldState.MAX_PEOPLE:
		push_error("Population must be between 1 and %d" % WorldState.MAX_PEOPLE)
		quit(1); return
	var world := WorldState.new()
	world.generate(42817)
	var land: Array[Vector2i] = []
	for y in world.height:
		for x in world.width:
			if world.walkable(Vector2i(x, y)): land.append(Vector2i(x, y))
	for i in population: world.add_person(land[(i * 13) % land.size()], false)
	for i in 100: world.step()
	world.profiling = true
	var start := Time.get_ticks_usec()
	for i in 100: world.step()
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	print("Population benchmark: %d initial, %d living, %d towns; 100 steps, %.2f ms, %.2f ms/step." % [population, world.people.size(), world.towns.size(), elapsed, elapsed / 100.0])
	print("Stages (microseconds): ", world.timings)
	quit()
