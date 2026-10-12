extends SceneTree

var failures := 0
var game

func check(condition: bool, description: String) -> void:
	if not condition: failures += 1; push_error("FAIL: " + description)

func settle(count: int = 3) -> void:
	for i in count: await process_frame

func touch(point: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index; event.position = point * root.content_scale_factor; event.pressed = pressed; event.canceled = canceled
	Input.parse_input_event(event)
	await settle()

func tap(point: Vector2) -> void:
	await touch(point, true)
	await touch(point, false)

func choose(index: int) -> void:
	await tap(game.tool_group_picker.get_global_rect().get_center())
	var popup: PopupMenu = game.tool_group_picker.get_popup()
	check(popup.visible, "native touch opens the group popup")
	var margin: float = popup.get_theme_stylebox("panel").get_content_margin(SIDE_TOP)
	var item_height := (float(popup.size.y) - margin - popup.get_theme_stylebox("panel").get_content_margin(SIDE_BOTTOM)) / popup.item_count
	await tap(Vector2(popup.position) + Vector2(40, margin + item_height * (index + 0.5)))
	check(not popup.visible and game.tool_group_picker.selected == index, "native touch selects a group and releases popup input")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(2160, 1080)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused = true; game.preferences.autosave = false
	game.system_ui_scale = 2.25; game._apply_ui_scale()
	var world := WorldState.new()
	world.paint(Vector2i(16, 16), 12, WorldState.Terrain.GRASS)
	game._set_world(world)
	game.view.zoom = 1.0; game.view.go_to_cell(Vector2i(16, 16), false)
	await settle(5)
	check(game.touch_ui and Input.is_emulating_mouse_from_touch(), "mobile UI enables mouse events needed by popup menus")
	await tap(game.tools_button.get_global_rect().get_center())
	await settle(20)
	check(game.tools_open, "native touch toggles the tools drawer once")
	for index in [1, 2, 3, 0]: await choose(index)
	game.paused = false; game._set_speed(5)
	var before := world.ticks
	await tap(game.tool_group_picker.get_global_rect().get_center())
	await create_timer(0.4).timeout
	check(world.ticks > before, "simulation continues while a responsive group popup is open")
	await tap(Vector2(800, 400))
	check(not game.tool_group_picker.get_popup().visible, "touch outside dismisses the popup")
	check(game.tools_open and not game.info_open and game.selected_cell == WorldState.NO_CELL, "dismissing a popup does not click through to the map")
	await tap(game.pause_button.get_global_rect().get_center())
	check(game.paused, "pause button responds after dismissing the popup")
	await tap(game.pause_button.get_global_rect().get_center())
	check(not game.paused, "pause button responds repeatedly")
	game.paused = true; game._finish_work(); game._set_speed(1)
	game._set_drawer("tools", false, false)
	game._select_tool("person")
	var point: Vector2 = game.view.cell_to_local(Vector2i(16, 16))
	await tap(point)
	check(world.people.size() == 1, "native touch and its emulated mouse event place exactly one resident")
	check(game.view.touches.is_empty(), "a completed native tap releases the map gesture")
	await touch(point, true)
	await touch(point, false, 0, true)
	check(world.people.size() == 1 and game.view.touches.is_empty(), "canceled touch does not place a resident or retain a finger")
	await touch(point, true)
	game._set_drawer("tools", true, false)
	game.tool_group_picker.show_popup()
	check(game.view.touches.is_empty(), "opening a popup cancels an unfinished map gesture")
	game._cancel_ui_input(game)
	check(not game.tool_group_picker.get_popup().visible and game.view.touches.is_empty(), "background cleanup dismisses popups and clears gestures")
	await touch(point, false)
	check(world.people.size() == 1, "late release from an interrupted gesture does not paint")
	game._set_drawer("tools", false, false)
	await tap(game.speed_button.get_global_rect().get_center())
	check(game.speed == 2, "controls remain responsive after interrupted input")
	game.paused = true; game._finish_work(); game.queue_free()
	await settle()
	print("Touch input: %d failures" % failures)
	quit(1 if failures else 0)
