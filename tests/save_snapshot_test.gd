extends SceneTree

class HeldSave extends WorldSaveJob:
	var holding := true
	func advance(budget_usec: int = 2500) -> bool:
		if snapshot_ready and holding: return false
		return super.advance(budget_usec)

var failures := 0

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error("FAIL: "+label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := WorldState.new()
	world.generate(42817); world.populate_demo()
	for i in 140: world._set_terrain(Vector2i(100000+i*32,0),WorldState.Terrain.GRASS)
	world.regions.trim(world)
	var cold := world.regions.cold.duplicate(true)
	var before := JSON.stringify(world.to_dict())
	var path := "user://snapshot-isolation-test.json"
	var save := WorldSaveJob.new(world,path)
	while not save.snapshot_ready and not save.finished: save.advance(1)
	check(world.regions.cold == cold,"capturing a cold world leaves cache residency and files unchanged")
	check(save.snapshot_ready,"snapshot becomes independent before obsolete-file cleanup")
	world.step()
	world.paint(Vector2i(100000,0),0,WorldState.Terrain.FOREST)
	world.paint(Vector2i(50000,0),2,WorldState.Terrain.FOREST)
	save.advance(0)
	var loaded := SaveStore.load_world(path)
	check(save.result == OK and loaded != null and JSON.stringify(loaded.to_dict()) == before,"continuing the world cannot alter a captured save")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.preferences.autosave = false
	game._set_world(world)
	game._set_speed(5)
	var held := HeldSave.new(world,"user://held-save-test.json")
	while not held.snapshot_ready and not held.finished: held.advance(1)
	game.save_job = held
	game.view.edits_locked = true
	game.paused = false
	var ticks := world.ticks
	for i in 40: await process_frame
	check(game.save_job == held and world.ticks > ticks,"simulation advances while save storage completion is delayed")
	check(not game.view.edits_locked,"captured save releases the brush lock")
	game.view.tool = "grass"
	game.view.brush_radius = 1
	game.view.apply_tool(Vector2i(60000,0))
	for i in 40: await process_frame
	check(world.terrain_at(Vector2i(60000,0)) == WorldState.Terrain.GRASS,"brush works while captured save awaits storage")
	held.holding = false
	game.paused = true
	game._finish_work()
	game.queue_free()
	await process_frame
	print("Save snapshot: ",failures," failures")
	quit(1 if failures else 0)
