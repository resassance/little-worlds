extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func advance(world: WorldState) -> int:
	var job := WorldWeatherStepJob.new(world)
	var units := 0
	while not job.finished:
		job.unit(); units += 1
	return units

func run() -> void:
	var world := WorldState.new(); world.paint(Vector2i.ZERO, 24, WorldState.Terrain.FOREST)
	world.weather.next_tick = 10000
	var event := WorldWeather.start(world, "drought", Vector2i.ZERO, 3, 20)
	var inside := world.food_at(Vector2i.ZERO)
	var outside := world.food_at(Vector2i(10, 0))
	var units := advance(world)
	check(world.food_at(Vector2i.ZERO) == inside - 1 and world.food_at(Vector2i(10, 0)) == outside, "drought changes food only inside its local area")
	check(world.drought_until == 0, "local weather does not activate legacy global drought")
	check(units > 49, "weather cells are applied through separate bounded units")
	var work_inside := 0
	var work_outside := 0
	for i in 20:
		world.ticks = i
		work_inside += int(WorldWeather.farm_work(world, Vector2i.ZERO))
		work_outside += int(WorldWeather.farm_work(world, Vector2i(10, 0)))
	check(work_inside == 5 and work_outside == 20, "drought slows only farms within the affected region")
	world.ticks = 20; advance(world)
	check(world.weather.active.is_empty() and WorldWeather.farm_work(world, Vector2i.ZERO), "weather ends on its deadline and farms recover automatically")
	WorldWeather.start(world, "rain", Vector2i.ZERO, 3, 20)
	world.set_fire(Vector2i.ZERO); world.set_fire(Vector2i(10, 0))
	advance(world)
	check(not world.fires.has(Vector2i.ZERO) and world.fires.has(Vector2i(10, 0)), "natural rain extinguishes nearby fire without clearing distant fire")
	check(WorldWeather.wet(world, Vector2i.ZERO) and not WorldWeather.wet(world, Vector2i(10, 0)), "rain protects only its local area from spreading fire")
	check(world.wet_until == 0, "natural rain does not impose global wetness")
	check(world.food_at(Vector2i.ZERO) == inside, "natural rain restores food gradually by one unit")
	WorldWeather.set_rate(world, 0)
	var rng_before: int = world.weather.rng
	world.ticks += 200; advance(world)
	check(world.weather.active.is_empty() and world.weather.rng == rng_before, "disabled events remain disabled without consuming random draws")
	world.weather.rate = 2
	var cold := WorldWeather.start(world, "frost", Vector2i.ZERO, 4, 20)
	world.add_person(Vector2i.ZERO, false)
	var member: Dictionary = world.people.back()
	check(WorldClimate.hunger_factor(world, member) > 1.0, "cold spell increases the need for warm clothing")
	member.x = 10
	check(WorldClimate.hunger_factor(world, member) == 1.0, "cold spell does not affect a resident outside its area")
	var saved := world.to_dict()
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(saved)))
	check(loaded != null and JSON.stringify(loaded.weather) == JSON.stringify(world.weather), "weather, its deadline and random stream survive JSON save/load")
	if loaded != null:
		check(WorldWeather.draw(loaded) == WorldWeather.draw(world), "loading cannot reroll the next weather outcome")
	saved.erase("weather")
	var legacy := WorldState.from_dict(saved)
	check(legacy != null and legacy.weather.active.is_empty(), "existing saves without weather load with an empty weather schedule")
	var invalid := world.to_dict(); invalid.weather.active[0].radius = 1000000
	check(WorldState.from_dict(invalid) == null, "loading rejects oversized weather areas")
	var rng_sim := world.rng.state
	for i in 10: WorldWeather.draw(world)
	check(world.rng.state == rng_sim, "weather uses its own random stream without rerolling human development")
	var first := WorldState.new(); first.paint(Vector2i.ZERO, 12, WorldState.Terrain.GRASS)
	first.weather.next_tick = 1; first.ticks = 1
	advance(first)
	check(not first.weather.active.is_empty(), "nature can produce an event on existing land without a player brush or residents")
	first.weather.active.clear(); first.climate.biome = 5
	for i in 60:
		WorldWeather.schedule(first)
		for value in first.weather.active: check(value.kind in ["rain", "frost", "storm"], "snow climate cannot roll a warm drought or dry thunderstorm")
		first.weather.active.clear()
	check(cold.until - cold.started <= 60 and event.until - event.started <= 60, "weather duration is bounded")
	var thunder := WorldState.new(); thunder.paint(Vector2i.ZERO, 20, WorldState.Terrain.FOREST)
	thunder.weather.next_tick = 10000
	var storm := WorldWeather.start(thunder, "thunder", Vector2i.ZERO, 8, 60)
	for i in 60:
		thunder.ticks = i; advance(thunder)
	check(not thunder.fires.is_empty() and storm.strike_tick >= 0, "automatic dry thunderstorms strike real land and ignite vegetation")
	var regions := thunder.region_count()
	thunder.weather.active.clear()
	WorldWeather.start(thunder, "rain", Vector2i(500000, -500000), 12, 20)
	advance(thunder)
	check(thunder.region_count() == regions, "weather over an empty ocean does not allocate terrain chunks")
	print("Weather: %d failures" % failures)
	quit(1 if failures else 0)
