extends SceneTree

var failures := 0

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error("FAIL: "+label)

func _initialize() -> void:
	var world := WorldState.new(); world.generate(42817); world.populate_demo()
	for i in 1200: world.step()
	var visible := 0
	for value in world.landscape.paths.values():
		if WorldLandscape.stage(WorldLandscape.wear_at(value,world.ticks)) > 0: visible += 1
	check(visible > 20,"autonomous settlers leave a visible trail network without player painting")
	check(not world.landscape.grounds.is_empty() and not world.stumps.is_empty(),"real construction and logging change the surroundings")
	var path := "user://landscape-autonomous.json"
	check(SaveStore.save_world(world,path) == OK,"autonomous landscape saves")
	var loaded := SaveStore.load_world(path)
	check(loaded != null and JSON.stringify(loaded.landscape.save()) == JSON.stringify(world.landscape.save()),"real terrain history restores exactly")
	for i in 80:
		world.step()
		if loaded != null: loaded.step()
	check(loaded != null and JSON.stringify(loaded.to_dict()) == JSON.stringify(world.to_dict()),"landscape and civilization continue identically after loading")
	check(WorldAudit.conserved(world),"living landscape preserves the economy")
	print("Autonomous landscape: ",visible," visible trail cells, ",world.stumps.size()," stumps; ",failures," failures")
	quit(1 if failures else 0)
