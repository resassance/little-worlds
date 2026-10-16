extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	var world := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/advanced-46-world.json")))
	check(world != null, "46-year world restores")
	if world == null: quit(1); return
	var maximum := 0
	var peaks := {}
	for i in WorldLife.YEAR:
		var job := WorldStepJob.new(world)
		while not job.finished:
			var start := Time.get_ticks_usec()
			job.advance(2000)
			maximum = maxi(maximum, Time.get_ticks_usec() - start)
		peaks[job.peak_phase] = maxi(int(peaks.get(job.peak_phase, 0)), job.max_unit_usec)
	check(maximum < 16000, "advanced world keeps simulation slices below one 60-Hz frame")
	check(WorldAudit.conserved(world), "sliced maritime search, construction and family updates conserve resources")
	var restored := WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true)))
	check(restored != null, "optimized advanced world restores")
	if restored != null:
		for i in WorldEconomy.DAY_TICKS: world.step(); restored.step()
		check(JSON.stringify(world.to_dict()) == JSON.stringify(restored.to_dict()), "derived route and site caches do not change the continuation after loading")
	var header := WorldSaveHeaderJob.new(world, [])
	var header_max := 0
	while not header.finished:
		var start := Time.get_ticks_usec()
		header.unit()
		header_max = maxi(header_max, Time.get_ticks_usec() - start)
	var expected := world.to_dict(false, false)
	expected.erase("chunks"); expected.erase("people"); expected.regions = []
	check(JSON.parse_string(header.result) == JSON.parse_string(JSON.stringify(expected,"",true,true)), "incremental header includes every existing save field")
	check(header_max < 16000, "save header has no whole-world serialization unit")
	var empty := WorldState.new()
	for i in WorldState.MAX_CHUNKS: empty._set_terrain(Vector2i(i * WorldState.CHUNK_SIZE, 0), WorldState.Terrain.GRASS)
	empty.ticks = WorldEconomy.DAY_TICKS - 1
	var access_before := empty.regions.clock
	empty.step()
	check(empty.regions.clock == access_before, "unpopulated land does not receive per-cell simulation")
	check(empty.regrowth == 1 and empty.regions.cold.size() == 1, "empty regions grow lazily and cache eviction is bounded per tick")
	var climate := WorldState.new()
	for i in 160: climate._set_terrain(Vector2i(i * WorldState.CHUNK_SIZE, 0), WorldState.Terrain.GRASS)
	climate.regrowth = 10
	var config := WorldClimateConfigureJob.new(climate, "belts", 0, 0, 64, true)
	var configuration_units := 0
	while not config.finished:
		config.unit(); configuration_units += 1
	check(configuration_units > 160 * WorldState.CHUNK_SIZE, "climate changes grow old regions in bounded batches")
	check(climate.regions.job_pins.is_empty(), "completed climate changes release temporary region pins")
	for key in climate.region_keys():
		check(climate.food_at(key * WorldState.CHUNK_SIZE) == climate.capacity(WorldState.Terrain.GRASS), "streamed climate changes preserve previously grown resources")
	var climate_access := climate.regions.clock
	var seasons := WorldClimateConfigureJob.new(climate, "belts", 0, 0, 64, false)
	seasons.advance(0)
	check(climate.regions.clock == climate_access, "season toggles do not visit empty land")
	var topology := WorldState.new()
	topology.paint(Vector2i.ZERO, 0, WorldState.Terrain.GRASS)
	check(topology.region_keys() == [Vector2i.ZERO], "region catalogue includes created land")
	topology.paint(Vector2i.ZERO, 0, WorldState.Terrain.WATER)
	topology.paint(Vector2i(64, 0), 0, WorldState.Terrain.GRASS)
	check(topology.region_keys() == [Vector2i(2, 0)], "same-sized region catalogue updates after land replacement")
	var sea := WorldState.new()
	sea.paint(Vector2i.ZERO, 0, WorldState.Terrain.GRASS)
	var coastal_home := {"id": 100, "x": 0, "y": 0}
	var coastal_navigation := WorldEconomy.navigation(sea, coastal_home)
	check(coastal_navigation.coasts.size() == 4 and coastal_navigation.quarries.is_empty(), "navigation records actual surrounding water")
	sea._set_terrain(Vector2i.RIGHT, WorldState.Terrain.MOUNTAIN)
	coastal_navigation = WorldEconomy.navigation(sea, coastal_home)
	check(coastal_navigation.coasts.size() == 3 and coastal_navigation.quarries.size() == 1, "water becoming rock updates coast and quarry lists despite unchanged walkability")
	sea._set_terrain(Vector2i.RIGHT, WorldState.Terrain.WATER)
	coastal_navigation = WorldEconomy.navigation(sea, coastal_home)
	check(coastal_navigation.coasts.size() == 4 and coastal_navigation.quarries.is_empty(), "rock becoming water restores coastline navigation")
	sea.paint(Vector2i.ZERO, 0, WorldState.Terrain.WATER)
	sea.paint(Vector2i(16, 0), 3, WorldState.Terrain.GRASS)
	var route := WorldSeaRouteJob.new(sea, Vector2i(-8, 0), Vector2i(48, 0))
	var route_units := 0
	while not route.finished: route.unit(); route_units += 1
	check(route.result.size() > 2 and route_units > 100, "obstacle routing yields throughout the search")
	for i in range(1, route.result.size()):
		check(WorldMaritime.segment_clear(sea, Vector2i(route.result[i - 1][0], route.result[i - 1][1]), Vector2i(route.result[i][0], route.result[i][1])), "sliced route avoids actual land")
	var cached := WorldSeaRouteJob.new(sea, Vector2i(-8, 0), Vector2i(48, 0))
	check(cached.finished and cached.result == route.result, "unchanged sea routes reuse the complete result")
	var revision := sea.sea_revision
	sea._set_terrain(Vector2i(16, 0), WorldState.Terrain.FOREST)
	check(sea.sea_revision == revision and not sea.sea_routes.is_empty(), "forest changes do not invalidate sea routes")
	sea._set_terrain(Vector2i(16, 0), WorldState.Terrain.WATER)
	check(sea.sea_revision > revision and sea.sea_routes.is_empty(), "changes to coastlines invalidate sea routes")
	print("Advanced slices max %.2f ms; header unit max %.2f ms; peaks %s; failures %d" % [maximum / 1000.0, header_max / 1000.0, peaks, failures])
	quit(1 if failures else 0)
