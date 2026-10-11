extends SceneTree

var game: Control
var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + description)

func _initialize() -> void:
 DirAccess.make_dir_recursive_absolute("res://artifacts")
 call_deferred("capture")

func settle_layout() -> void:
 for i in 5:
  await process_frame
 await create_timer(0.28).timeout
 await RenderingServer.frame_post_draw

func snapshot(name_value: String) -> void:
 await settle_layout()
 var result = root.get_texture().get_image().save_png("res://artifacts/" + name_value + ".png")
 check(result == OK, "screenshot saved: " + name_value)

func capture() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game._toggle_pause()
 var demo := WorldState.new()
 demo.generate(42817)
 demo.populate_demo()
 for i in 1200: demo.step()
 game._set_world(demo)
 await settle_layout()
 var default_zoom: float = game.view.zoom
 game.view.fit_map()
 check(default_zoom > game.view.zoom, "default camera is closer than whole-island fit")
 game.view.focus_island()
 check(WorldEconomy.count(demo, demo.towns[0], "house") > 0 and WorldEconomy.count(demo, demo.towns[0], "farm") > 0 and WorldEconomy.count(demo, demo.towns[0], "store") > 0, "rendered demo contains real completed house, farm and store")
 check(game.view.job_textures.size() == WorldEconomy.JOBS.size(), "every profession has a readable sprite color")
 await snapshot("world-desktop")
 check(not game.sidebar.visible and not game.tool_panel.visible, "both drawers start hidden")
 check(game.view.size == game.size, "map uses full viewport")
 check(game.pause_button.tooltip_text.contains("Продолжить"), "paused state has correct action")
 var camera_offset: Vector2 = game.view.offset
 var camera_zoom: float = game.view.zoom
 game._toggle_tools()
 await snapshot("world-tools")
 check(game.tool_panel.visible and game.tools_open, "tools drawer opens")
 check(game.view.offset == camera_offset and game.view.zoom == camera_zoom, "drawer does not move or zoom camera")
 game._toggle_tools()
 await settle_layout()
 check(not game.tool_panel.visible, "closed drawer stops capturing map input")
 game._toggle_tools(); game._toggle_tools(); game._toggle_tools()
 await settle_layout()
 check(game.tools_open and game.tool_panel.visible, "rapid toggles end in expected state")
 game._toggle_tools()
 await settle_layout()
 var target := Vector2i(demo.towns[0].x + 7, demo.towns[0].y + 4)
 game._select_tool("forest")
 game.view.apply_tool(target)
 check(demo.terrain_at(target) == WorldState.Terrain.FOREST, "terrain tool changes map")
 check(not game.view.effects.is_empty(), "tool creates visual feedback")
 game._select_tool("person")
 var before := demo.people.size()
 game.view.apply_tool(target)
 check(demo.people.size() == before + 1, "person tool places a resident")
 game._select_tool("fire")
 game.view.hover = target
 game.view.apply_tool(target)
 check(not demo.fires.is_empty(), "lightning tool starts a fire")
 var effect = game.view.effects.back()
 effect.age = 0.04
 await snapshot("world-lightning")
 game._select_tool("rain")
 game.view.apply_tool(target)
 check(demo.fires.is_empty(), "rain tool extinguishes fire")
 await snapshot("world-rain")
 game._select_tool("inspect")
 game.view.apply_tool(Vector2i(demo.towns[0].x, demo.towns[0].y))
 await settle_layout()
 check(game.inspector_label.text.contains(demo.towns[0].name), "inspection displays town details")
 await snapshot("world-info")
 check(game.info_open, "inspection reveals info drawer")
 check(game.inspector_label.text.contains("Дома:") and game.inspector_label.text.contains("мес."), "town inspection shows real buildings and food runway")
 game.view.go_to_cell(Vector2i(demo.towns[0].x, demo.towns[0].y))
 game.view.zoom_by(3.0 / game.view.zoom)
 await snapshot("world-economy")
 var resident: Dictionary = {}
 for candidate in demo.people:
  var structure: Dictionary = demo.building_at(Vector2i(candidate.x, candidate.y))
  if structure.is_empty() or structure.kind != "camp":
   resident = candidate
   break
 check(not resident.is_empty(), "demo has an inspectable resident outside camp")
 if not resident.is_empty():
  game._inspect(Vector2i(resident.x, resident.y))
  check(game.inspector_label.text.contains(resident.name) and game.inspector_label.text.contains(WorldEconomy.JOBS[resident.job]), "resident inspection shows name and actual profession")
  demo.step()
  check(game.selected_cell == Vector2i(resident.x, resident.y) and game.inspected_person_id == resident.id, "inspection follows the selected resident while they work")
  await snapshot("world-resident")
 var child: Dictionary = {}
 for candidate in demo.people:
  if not WorldLife.adult(demo, candidate):
   child = candidate
   break
 check(not child.is_empty(), "rendered demo contains an actual newborn")
 if not child.is_empty():

  for i in demo.people.size():
   game._inspect(Vector2i(child.x, child.y))
   if game.inspected_person_id == child.id: break
  check(game.inspected_person_id == child.id, "clicks select a child among people sharing a tile")
  check(game.inspector_label.text.contains("Малыш") and game.inspector_label.text.contains("Родители:") and game.inspector_label.text.contains("Опекун:"), "child inspection shows age, parents and caregiver")
  game.view.go_to_cell(Vector2i(child.x, child.y))
  await snapshot("world-family")
 game._toggle_info()
 await settle_layout()
 demo.step()
 check(not game.info_open, "simulation refresh does not reopen hidden info")
 game.view.zoom_by(1.3)
 var button_zoom: float = game.view.zoom
 game.view.zoom_by(1.0 / 1.3)
 check(game.view.zoom < button_zoom, "explicit zoom buttons work in both directions")
 var initial_zoom: float = game.view.zoom
 var camera_anchor = game.view.size * 0.5
 var before_zoom = game.view.local_to_cell(camera_anchor)
 game.view._zoom_at(camera_anchor, 1.8)
 check(game.view.zoom > initial_zoom, "camera zoom changes scale")
 check(game.view.local_to_cell(camera_anchor).distance_to(before_zoom) <= 1, "zoom keeps cursor anchor")
 await snapshot("world-closeup")
 game._ask_generation()
 await snapshot("world-new-dialog")
 check(game.generation_dialog.size.y < 330, "generation dialog stays compact")
 check(game.generation_dialog.size.x < root.size.x, "generation dialog fits viewport")
 game.generation_dialog.hide()
 game._world_menu_selected(3)
 await snapshot("world-settings")
 game.settings_dialog.hide()
 game.view.reduce_motion = true
 var visual_time = game.view.visual_time
 await process_frame
 await process_frame
 check(game.view.visual_time == visual_time, "reduced motion freezes decorative time")
 game.view.reduce_motion = false
 game._set_speed(5)
 check(game.speed_button.text == "×5", "single speed control displays current speed")
 game._cycle_speed()
 check(game.speed == 1, "speed button cycles back to normal")
 game._set_speed(1)
 root.size = Vector2i(844, 480)
 await settle_layout()
 if not child.is_empty():
  game.inspected_person_id = child.id
  game._inspect(Vector2i(child.x, child.y), false)
  game._toggle_info()
  await snapshot("world-mobile-family")
  check(game.sidebar.position.y + game.sidebar.size.y <= root.size.y - 60, "family drawer fits short phone viewport")
  var family_scroll: VScrollBar = game.history_scroll.get_v_scroll_bar()
  check(family_scroll.max_value > family_scroll.page, "long family details and history remain scrollable")
  game._toggle_info()
  await settle_layout()
 game.view.focus_island()
 game.selected_cell = WorldState.NO_CELL
 game._select_tool("inspect")
 await snapshot("world-mobile")
 check(not game.sidebar.visible and not game.tool_panel.visible, "compact screen starts uncluttered")
 game._toggle_tools()
 await snapshot("world-mobile-tools")
 game._toggle_info()
 await settle_layout()
 check(game.info_open and not game.tools_open, "phone shows only one drawer at a time")
 game._toggle_info()
 await settle_layout()
 var resize_zoom: float = game.view.zoom
 root.size = Vector2i(900, 520)
 await settle_layout()
 check(game.view.zoom == resize_zoom, "viewport resize preserves chosen zoom")
 root.size = Vector2i(844, 480)
 await settle_layout()
 check(game.size.x <= 844, "compact layout fits viewport width")
 check(game.view.size.x > 400 and game.view.size.y >= 220, "compact screen preserves playable map")

 game._select_tool("grass")
 var screen_cell = game.view.cell_to_local(target)
 var touch := InputEventScreenTouch.new()
 touch.index = 0
 touch.position = screen_cell
 touch.pressed = true
 game.view._gui_input(touch)
 touch.pressed = false
 game.view._gui_input(touch)
 check(demo.terrain_at(target) == WorldState.Terrain.GRASS, "touch tap applies selected tool")
 game._select_tool("pan")
 var one := InputEventScreenTouch.new()
 one.index = 0; one.position = Vector2(100, 100); one.pressed = true
 var two := InputEventScreenTouch.new()
 two.index = 1; two.position = Vector2(200, 100); two.pressed = true
 game.view._gui_input(one); game.view._gui_input(two)
 var pinch_before = game.view.zoom
 var drag := InputEventScreenDrag.new()
 drag.index = 1; drag.position = Vector2(250, 100)
 game.view._gui_input(drag)
 check(game.view.zoom > pinch_before, "two-finger pinch zooms map")
 one.pressed = false; two.pressed = false
 game.view._gui_input(one); game.view._gui_input(two)
 var previous_tool: String = game.view.tool
 game._toggle_hud()
 check(not game.hud.visible and game.reveal_button.visible, "clean mode hides HUD and leaves a return button")
 check(game.view.tool == "pan", "clean mode pans instead of painting")
 await snapshot("world-clean")
 game._toggle_hud()
 check(game.hud.visible and game.view.tool == previous_tool, "leaving clean mode restores selected tool")
 game.view._zoom_at(game.view.size * 0.5, 1000.0)
 check(game.view.zoom == 12.0, "close zoom supports 12x with a safe upper bound")
 game.view._zoom_at(game.view.size * 0.5, 0.00000001)
 check(game.view.zoom == WorldView.MIN_ZOOM, "far zoom respects lower bound")

 root.size = Vector2i(1280, 800)
 await settle_layout()
 var distant := Vector2i(-900000, 700000)
 game.view.go_to_cell(distant)
 check(game.view.local_to_cell(game.view.size * 0.5) == distant, "camera jumps exactly to far negative coordinates")
 game._select_tool("forest")
 game.view.brush_radius = 64
 game.view.apply_tool(distant)
 check(demo.walkable(distant), "large brush creates remote continent through game view")
 for delta in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.ONE]: demo.add_person(distant + delta, false)
 for i in 100: demo.step()
 game.view.brush_radius = 2
 game._select_tool("inspect")
 game.view.apply_tool(distant)
 await settle_layout()
 check(game.inspector_label.text.contains("-900000"), "inspection supports negative world coordinates")
 game._toggle_info()
 await snapshot("world-distant")
 game._world_menu_selected(4)
 await snapshot("world-navigation")
 check(game.destination_picker.item_count >= 4, "navigation lists both remote settlements")
 game.coordinate_x.value = 64
 game.coordinate_y.value = 64
 await settle_layout()
 game.navigation_dialog.confirmed.emit()
 game.navigation_dialog.hide()
 check(game.view.local_to_cell(game.view.size * 0.5) == Vector2i(64, 64), "navigation dialog returns to founding island")
 game.view.fit_map()
 await snapshot("world-overview")
 check(game.view.zoom < 0.001, "whole-world fit includes very distant continents")
 check(game.view.chunk_textures.size() <= WorldView.CACHE_LIMIT, "detailed texture cache stays bounded")
 var old_count: int = demo.chunks.size()
 game.view.go_to_cell(Vector2i(600000, -700000))
 await settle_layout()
 check(demo.chunks.size() == old_count, "camera exploration never allocates world data")

 var learning := WorldState.new()
 learning.generate(42817)
 learning.populate_demo()
 for i in 3600: learning.step()
 check(learning.metrics.lessons > 0, "community autonomously teaches through actual meetings")
 game._set_world(learning)
 var apprentice: Dictionary = {}
 for candidate in learning.people:
  if not WorldLife.adult(learning, candidate) and not candidate.trained_by.is_empty():
   apprentice = candidate
   break
 check(not apprentice.is_empty(), "real child has learned a craft")
 if not apprentice.is_empty():
  game.view.go_to_cell(Vector2i(apprentice.x, apprentice.y))
  game.view.zoom_by(6.0 / game.view.zoom)
  for i in learning.people.size() + 1:
   game._inspect(Vector2i(apprentice.x, apprentice.y))
   if game.inspected_person_id == apprentice.id: break
  check(game.inspected_person_id == apprentice.id, "repeated inspection selects pupils even at a camp")
  check(game.inspector_label.text.contains("Навыки") and game.inspector_label.text.contains("учитель") and game.inspector_label.text.contains("Друзья:"), "apprentice card explains skills, teacher and friendships")
  await snapshot("world-learning")
  root.size = Vector2i(844, 480)
  await snapshot("world-mobile-learning")
  check(game.sidebar.position.y + game.sidebar.size.y <= root.size.y - 60, "expanded skills card fits phone with scrolling")
 root.size = Vector2i(1280, 800)
 await settle_layout()
 var home: Dictionary = learning.towns[0]
 check(WorldEconomy.count(learning, home, "workshop") > 0 and WorldEconomy.count(learning, home, "archive") > 0, "real society builds its workshop and archive")
 check(WorldDevelopment.profile(learning, home).engineering.mastered > 0 and learning.metrics.discoveries >= 4, "autonomous community reaches the craft stage through four discoveries")
 game.inspected_person_id = -1
 game.selected_cell = WorldState.NO_CELL
 game.view.go_to_cell(Vector2i(home.x, home.y))
 game._inspect(Vector2i(home.x, home.y))
 check(game.inspector_label.text.contains("Строительство и инженерия:") and game.inspector_label.text.contains("Хранение пищи: применяется") and game.inspector_label.text.contains("Архивы: 1"), "town card shows actual society stage, technology use and infrastructure")
 await snapshot("world-society")
 root.size = Vector2i(844, 480)
 await snapshot("world-mobile-society")
 check(game.sidebar.position.y + game.sidebar.size.y <= root.size.y - 60, "society card fits phone with scrolling")
 game.sidebar.hide()
 game._world_menu_selected(5)
 await snapshot("world-mobile-climate")
 check(game.climate_dialog.size.y < root.size.y - 60,"climate dialog fits short phone screen")
 game.climate_mode.selected=1; game.climate_scale.value=1024; game.climate_seasons.button_pressed=true
 game.climate_dialog.confirmed.emit(); game.climate_dialog.hide()
 while game.climate_update_job != null: await process_frame
 check(game.world.climate.mode=="belts" and game.world.climate.seasons,"climate dialog changes real simulation settings")
 game._select_tool("biome_5")
 game.view.apply_tool(Vector2i(home.x,home.y))
 check(WorldClimate.biome(game.world,Vector2i(home.x,home.y))==5,"biome tool paints climate without replacing settlement")
 game.view.last_painted=WorldState.NO_CELL
 game._select_tool("inspect")
 game._world_menu_selected(6)
 await snapshot("world-mobile-help")
 check(game.help_dialog.size.y < root.size.y - 60,"scrolling tutorial keeps close controls on screen")
 game.help_dialog.hide()
 game._world_menu_selected(10)
 await snapshot("world-mobile-sculpt")
 check(game.sculpt_dialog.size.y < root.size.y - 60,"continent creation dialog fits phone screen")
 game.sculpt_dialog.hide()
 print("Visual/input: %d checks, %d failures. Screenshots saved in artifacts/." % [checks, failures])
 quit(0 if failures == 0 else 1)
