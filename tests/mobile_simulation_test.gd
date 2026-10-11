extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	for count in [200, 2000]:
		var world := WorldState.new()
		world.generate(42817)
		var land: Array[Vector2i] = []
		for y in world.height:
			for x in world.width:
				if world.walkable(Vector2i(x, y)): land.append(Vector2i(x, y))
		for i in count: world.add_person(land[(i * 13) % land.size()], false)
		var serial := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
		check(serial != null, "full-step reference restores the initial population")
		var slices := 0
		var maximum := 0
		var durations: Array[int] = []
		var total := 0
		var peaks := {}
		for i in 120:
			var job := WorldStepJob.new(world)
			check(world.stepping, "tick locks model until completion")
			while not job.finished:
				var before := Time.get_ticks_usec()
				job.advance(4000)
				var elapsed := Time.get_ticks_usec() - before
				maximum = maxi(maximum, elapsed)
				durations.append(elapsed)
				total += elapsed
				slices += 1
			if serial != null: serial.step()
			peaks[job.peak_phase] = maxi(int(peaks.get(job.peak_phase, 0)), job.max_unit_usec)
			check(not world.stepping and not world.workforce.active and not world.population.active, "tick releases derived context")
		check(WorldAudit.conserved(world), "time sliced economy conserves all resources")
		check(world.ticks == 120, "time slicing completes every requested tick")
		check(serial != null and JSON.stringify(world.to_dict()) == JSON.stringify(serial.to_dict()), "full and sliced simulation preserve the same population, decisions, RNG and discoveries")
		durations.sort()
		print("Sliced simulation: %d people, %d slices, mean %.2f ms, p95 %.2f ms, max %.2f ms" % [count,slices,total/1000.0/slices,durations[int(durations.size()*.95)]/1000.0,maximum/1000.0])
		print("Largest units: ", peaks)
		var destination := "user://mobile-test-%d.json" % count
		var save := WorldSaveJob.new(world, destination)
		var save_slices := 0
		var save_max := 0
		while not save.finished:
			var before := Time.get_ticks_usec()
			save.advance(2500)
			save_max = maxi(save_max, Time.get_ticks_usec() - before)
			save_slices += 1
		check(save.result == OK, "incremental save succeeds")
		var restored := SaveStore.load_world(destination)
		check(restored != null, "incremental save restores")
		if restored != null:
			check(JSON.parse_string(JSON.stringify(world.to_dict())) == JSON.parse_string(JSON.stringify(restored.to_dict())), "incremental save preserves the complete world")
			world.step(); restored.step()
			check(JSON.parse_string(JSON.stringify(world.to_dict())) == JSON.parse_string(JSON.stringify(restored.to_dict())), "incremental save resumes deterministically")
		print("Sliced save: %d people, %d slices, max %.2f ms" % [count,save_slices,save_max/1000.0])
	print("Mobile simulation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
