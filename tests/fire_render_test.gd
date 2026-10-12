extends SceneTree

var failures := 0
var view: WorldView

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: "+description)

func frame() -> void:
	view._process(0.016)
	await process_frame; await RenderingServer.frame_post_draw

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280,800)
	view = WorldView.new(); root.add_child(view); view.set_process(false); view.size = Vector2(1280,800)
	var world := WorldState.new(); world.paint(Vector2i.ZERO,24,WorldState.Terrain.FOREST)
	view.set_world(world); view.zoom = 2.0; view.go_to_cell(Vector2i.ZERO,false)
	for i in 80: await frame()
	world.ignite(Vector2i.ZERO,8)
	for i in 12: await frame()
	check(view.fire_multimesh.visible_instance_count > 0 and view.fire_multimesh.visible_instance_count <= world.fires.size(),"nearby fires are grouped into one draw mesh")
	var image := root.get_texture().get_image()
	var flame := image.get_pixelv(Vector2i(view.cell_to_local(Vector2i.ZERO)))
	check(flame.r > flame.g+0.04 and flame.g > flame.b+0.1,"fire atlas and shader render the bright flame core")
	image.save_png("res://artifacts/fire-render.png")
	for i in 4: view.zoom = 0.2 if i%2 == 0 else 2.0; view.go_to_cell(Vector2i.ZERO,false); await frame()
	check(view.fire_multimesh.visible_instance_count <= world.fires.size(),"fire detail changes remain bounded")
	world.rain(Vector2i.ZERO,12)
	for i in 4: await frame()
	check(view.fire_multimesh.visible_instance_count == 0,"rain removes the fire mesh on the next prepared frame")
	image = root.get_texture().get_image()
	var ground := image.get_pixelv(Vector2i(view.cell_to_local(Vector2i.ZERO)))
	check(ground.g > ground.r,"extinguished fire reveals the forest underneath")
	view.queue_free(); await process_frame
	print("Fire rendering: %d failures" % failures)
	quit(1 if failures else 0)
