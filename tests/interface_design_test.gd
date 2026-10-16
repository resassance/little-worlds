extends SceneTree

var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw

func count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += count_nodes(child)
	return count

func select_building(value: Dictionary) -> void:
	game.selected_cell = WorldState.NO_CELL
	game.inspected_person_id = -1
	game._inspect(Vector2i(value.x,value.y))
	game._set_drawer("info",true,false)

func tap(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = 0; event.position = point*root.content_scale_factor; event.pressed = pressed
		Input.parse_input_event(event)
		for i in 3: await process_frame

func capture(name_value: String) -> void:
	await settle()
	root.get_texture().get_image().save_png("res://artifacts/interface-"+name_value+".png")

func run() -> void:
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.paused = true; game.preferences.autosave = false
	var world := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/living-civilizations-world.json")))
	check(world!=null,"city fixture loads")
	world.log_event("Освоена технология","Каменная гавань: обработка камня.")
	world.log_event("Живительный дождь","На остров вернулась влага.")
	game._set_world(world); game.status_panel.hide(); game.view.reduce_motion = true
	var home: Dictionary = world.towns[0]
	game.view.zoom = 2.0; game.view.go_to_cell(Vector2i(home.x,home.y),false)
	var selected: Dictionary = {}
	for value in world.buildings:
		if value.town==home.id and value.kind=="archive": selected = value; break
	check(not selected.is_empty(),"fixture contains an archive")
	if selected.is_empty(): selected = WorldEconomy.add_building(world,home,"archive",Vector2i(home.x+14,home.y),true)
	var before := JSON.stringify(world.to_dict())
	select_building(selected)
	check(game.inspector.selection_kind=="building","first tap selects building independently of nearby settlement")
	check(game.inspector.title_label.text==WorldEconomy.NAMES[selected.kind],"building is the primary heading")
	check(game.inspector.building_card.visible and not game.inspector.metrics.visible,"building omits settlement summary cards")
	check(not game.inspector.building_card.explanation.visible,"long explanations start hidden")
	game.inspector.building_card.help_button.pressed.emit()
	check(game.inspector.building_card.explanation.visible,"building meaning is available by tap")
	game.inspector.building_card.help_button.pressed.emit()
	game._refresh_inspector()
	var nodes := count_nodes(game.inspector)
	for i in 20: game._refresh_inspector()
	check(count_nodes(game.inspector)==nodes,"building refresh reuses controls")
	check(JSON.stringify(world.to_dict())==before,"building UI is read only")
	await capture("archive-desktop")
	game.inspector.building_card.settlement.pressed.emit()
	check(game.inspector.selection_kind=="town","building links to its settlement")
	await capture("settlement-desktop")
	game._set_drawer("tools",true,false)
	await capture("buttons-desktop")
	game._set_drawer("tools",false,false)
	var unfinished: Dictionary = {}
	for value in world.buildings:
		if not value.ready: unfinished = value; break
	if unfinished.is_empty(): unfinished = WorldEconomy.add_building(world,home,"tower",Vector2i(home.x+18,home.y+6))
	unfinished.delivered = mini(5,WorldEconomy.COST[unfinished.kind]); unfinished.work = 3
	select_building(unfinished)
	var card: BuildingCard = game.inspector.building_card
	check(card.materials.visible and card.work_bar.visible,"construction exposes materials and progress")
	check(card.work_bar.value==unfinished.work and card.work_bar.max_value==WorldEconomy.WORK[unfinished.kind],"construction uses actual work")
	await capture("construction-desktop")
	var loom := WorldEconomy.add_building(world,home,"loom",Vector2i(home.x+22,home.y+6),true)
	select_building(loom)
	check(game.inspector.building_card.output.get_child_count()==1,"loom exposes a material conversion")
	await capture("production-desktop")
	game._set_info_tab(true); game._refresh_inspector(); await settle()
	check(game.world_info.records.size()>0,"chronicle builds event cards")
	var record: Dictionary = game.world_info.records[0]
	check(not record.message.visible,"history descriptions start collapsed")
	record.button.button_pressed = true
	check(record.message.visible,"event description opens on tap")
	var updated: int = game.world_info.updates
	var history_nodes := count_nodes(game.world_info)
	for i in 20: game._refresh_inspector()
	check(game.world_info.updates==updated and count_nodes(game.world_info)==history_nodes,"unchanged history does not rebuild")
	await capture("history-desktop")
	var opened_key: String = record.key
	world.log_event("Новая семья","Жители решили жить вместе.")
	game._refresh_inspector()
	var retained_open := false
	for row in game.world_info.records:
		if row.key==opened_key: retained_open = row.message.visible
	check(retained_open,"new records preserve expanded event state")
	game.world_info.filter.select(1); game.world_info.filter.item_selected.emit(1)
	for row in game.world_info.records:
		if row.panel.visible: check(game.world_info.category({"title":row.title.text})==1,"knowledge filter excludes other events")
	check(not game.world_info.empty_label.visible,"knowledge filter has matching fixture events")
	var record_ids: Array[int] = []
	for row in game.world_info.records: record_ids.append(row.panel.get_instance_id())
	game.world_info.filter.select(0); game.world_info.filter.item_selected.emit(0)
	for i in record_ids.size(): check(record_ids[i]==game.world_info.records[i].panel.get_instance_id(),"filters reuse record panels")
	Input.set_emulate_mouse_from_touch(true)
	for screen in [[Vector2i(2160,1080),2.25],[Vector2i(2400,1080),3.0],[Vector2i(1080,2400),3.0],[Vector2i(1180,820),2.0]]:
		root.size = screen[0]; game.touch_ui = true; game.system_ui_scale = screen[1]; game.preferences.ui_scale = 1
		game.inspector.touch_ui = true; game.inspector.building_card.touch_ui = true; game.world_info.touch_ui = true
		game._apply_ui_scale(); game._build_theme(); game._prepare_touch_ui(game); game._responsive()
		select_building(unfinished); await settle()
		check(Rect2(Vector2.ZERO,game.size).encloses(game.sidebar.get_global_rect()),"building panel fits "+str(screen[0]))
		check(game.history_scroll.get_h_scroll_bar().max_value<=game.history_scroll.size.x+1,"building has no horizontal overflow")
		for token in game.inspector.building_card.materials.get_children():
			if token.visible: check(token.size.y*game.ui_scale/game.system_ui_scale>=47.9,"material chips have 48 dp touch targets")
		if screen[0]==Vector2i(2160,1080):
			var token: Button = game.inspector.building_card.materials.get_child(0)
			await tap(token.get_global_rect().get_center())
			check(game.inspector.building_card.explanation.visible,"native touch opens a material explanation")
			game.inspector.building_card.explanation.hide()
		await capture("construction-%dx%d" % [screen[0].x,screen[0].y])
		select_building(selected); await capture("archive-%dx%d" % [screen[0].x,screen[0].y])
		game._set_info_tab(true); game._refresh_inspector(); await settle()
		check(game.world_info.filter.size.y*game.ui_scale/game.system_ui_scale>=47.9,"history filter has a 48 dp target")
		check(game.history_scroll.get_h_scroll_bar().max_value<=game.history_scroll.size.x+1,"history has no horizontal overflow")
		if screen[0]==Vector2i(2160,1080):
			await tap(game.world_info.filter.get_global_rect().get_center())
			var popup: PopupMenu = game.world_info.filter.get_popup()
			check(popup.visible,"native touch opens the archive filter")
			var margin: float = popup.get_theme_stylebox("panel").get_content_margin(SIDE_TOP)
			var height := (float(popup.size.y)-margin-popup.get_theme_stylebox("panel").get_content_margin(SIDE_BOTTOM))/popup.item_count
			await tap(Vector2(popup.position)+Vector2(40,margin+height*1.5))
			check(not popup.visible and game.world_info.filter.selected==1,"native touch changes archive category and releases input")
			game.world_info.filter.select(0); game.world_info.filter.item_selected.emit(0)
		check(game.world_info.people_label.get_line_count()==1,"population summary does not wrap digits")
		await capture("history-%dx%d" % [screen[0].x,screen[0].y])
		game.preferences.ui_scale = 0.85; game._apply_ui_scale(); game._prepare_touch_ui(game); game._responsive()
		game.world_info.rebuild(); await settle()
		for row in game.world_info.records:
			if row.panel.visible: check(row.button.size.y*game.ui_scale/game.system_ui_scale>=47.9,"compact history retains 48 dp targets")
	game.queue_free(); await process_frame
	print("Interface design: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
