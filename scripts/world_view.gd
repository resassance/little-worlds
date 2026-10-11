class_name WorldView
extends Control


signal cell_selected(cell: Vector2i)
signal feedback(message: String)

const TILE := 8
const MIN_ZOOM := 0.00001
const CACHE_LIMIT := 96
const HALO := 8
const MAX_ZOOM := 12.0
const COLORS := [Color("295d70"), Color("e2cc9b"), Color("a2bd78"), Color("829f65"), Color("959b86")]
const TOOL_COLORS := {"water": Color("85ced0"), "sand": Color("f2d5a0"), "grass": Color("b4d98d"), "forest": Color("91c784"), "mountain": Color("c9ccb7"), "person": Color("b0e5d2"), "fire": Color("ffb072"), "rain": Color("93d6e4")}
var world: WorldState
var texture: ImageTexture
var chunk_textures: Dictionary = {}
var overview_textures: Dictionary = {}
var camera_origin := Vector2i.ZERO
var cache_clock := 0
var minimap_bounds := Rect2i()
var baking_shores: Array[Vector2i] = []
var texture_dirty := false
var zoom: float = 0.85
var offset := Vector2.ZERO
var tool: String = "inspect"
var brush_radius: int = 2
var hover := WorldState.NO_CELL
var selected := WorldState.NO_CELL
var dragging := false
var panning := false
var last_painted := WorldState.NO_CELL
var touches: Dictionary = {}
var pinch_distance: float = 0.0
var last_touch := Vector2.ZERO
var touch_painted: bool = false
var visual_time := 0.0
var person_positions: Dictionary = {}
var person_directions: Dictionary = {}
var visible_people: Array[Dictionary] = []
var population_view_signature: Array = []
var effects: Array[Dictionary] = []
var last_effect_time := -1.0
var camp_texture: ImageTexture
var store_texture: ImageTexture
var workshop_texture: ImageTexture
var archive_texture: ImageTexture
var vessel_textures := {}
var industry_textures := {}
var job_textures: Dictionary = {}
var house_texture: ImageTexture
var person_texture: ImageTexture
var alert_texture: ImageTexture
var rain_texture: ImageTexture
var label_font: Font
var reduce_motion := false
var show_minimap := false:
	set(value):
		if show_minimap != value: texture_dirty = true
		show_minimap = value
var interface_visible := true
var last_view_size := Vector2.ZERO
var edits_locked := false
var pending_tools: Array[Dictionary] = []
var bake_job: WorldChunkBakeJob
var bake_queue: Array[Dictionary] = []
var bake_pending: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	house_texture = PixelArt.sprite_texture(PixelArt.HOUSE)
	camp_texture = PixelArt.sprite_texture(PixelArt.CAMP)
	store_texture = PixelArt.sprite_texture(PixelArt.STORE)
	workshop_texture = PixelArt.sprite_texture(PixelArt.WORKSHOP)
	archive_texture = PixelArt.sprite_texture(PixelArt.ARCHIVE)
	for kind in ["kiln","loom","forge","market","school","council","dock","port","boat","sailboat"]: industry_textures[kind]=PixelArt.building_texture(kind)
	vessel_textures = {"boat": PixelArt.vessel_texture(false), "sailboat": PixelArt.vessel_texture(true)}
	var job_colors := {"settler": ["c0e7d5", "83c4c0"], "forager": ["b9d594", "968a5b"], "logger": ["e7ba83", "986b47"], "builder": ["b9b1d3", "887aa6"], "farmer": ["9ad4b0", "669979"], "child": ["e9caa7", "c4a58c"], "teen": ["c6dcb4", "94ae87"], "carer": ["d9b9cd", "ad8ea5"], "teacher": ["dfca82", "a38a57"], "researcher": ["aac9dc", "7596b4"]}
	job_colors.merge({"miner": ["b8bcb3", "7b887d"], "artisan": ["d9a495", "aa766c"], "fisher": ["8bc8d1", "618aa2"], "sailor": ["e2d7a8", "779caa"], "merchant": ["d3b6da", "967fa8"]})
	for job in job_colors:
		var colors: Array = job_colors[job]
		job_textures[job] = PixelArt.sprite_texture(PixelArt.PERSON, {"c": Color(colors[0]), "a": Color(colors[1])})
	person_texture = PixelArt.sprite_texture(PixelArt.PERSON)
	alert_texture = PixelArt.sprite_texture(PixelArt.PERSON, {"c": Color("e9946d"), "a": Color("b96757")})
	rain_texture = PixelArt.icon("rain")
	label_font = preload("res://assets/fonts/DejaVuSans.ttf")
	resized.connect(_on_resize)
	last_view_size = size
	mouse_exited.connect(func(): hover = WorldState.NO_CELL; dragging = false; panning = false; queue_redraw())

func set_world(value: WorldState) -> void:
	if world != null and world.terrain_changed.is_connected(_invalidate_texture):
		world.terrain_changed.disconnect(_invalidate_texture)
	if world != null and world.changed.is_connected(_invalidate_population_view): world.changed.disconnect(_invalidate_population_view)
	world = value
	world.terrain_changed.connect(_invalidate_texture)
	world.changed.connect(_invalidate_population_view)
	person_positions.clear()
	person_directions.clear()
	visible_people.clear(); population_view_signature.clear()
	effects.clear()
	camera_origin = Vector2i.ZERO
	chunk_textures.clear()
	overview_textures.clear()
	bake_job = null; bake_queue.clear(); bake_pending.clear()
	pending_tools.clear()
	rebuild_texture()
	selected = WorldState.NO_CELL
	focus_island()

func fit_map() -> void:
	if world == null or size.x < 1:
		return
	var bounds := world.land_bounds()
	var span := Vector2(bounds.size + Vector2i(16, 16)) * TILE
	zoom = clampf(minf((size.x - 32) / span.x, (size.y - 56) / span.y), MIN_ZOOM, 3.0)
	go_to_cell(bounds.position + bounds.size / 2, false)
	queue_redraw()

func _on_resize() -> void:

	if last_view_size == Vector2.ZERO:
		last_view_size = size
		if world != null: focus_island()
		return
	offset += (size - last_view_size) * 0.5
	last_view_size = size
	if world != null: _clamp_camera()
	queue_redraw()

func focus_island() -> void:
	if world == null: return

	zoom = maxf(0.8, minf(size.x, size.y) / 700.0)
	var cell := Vector2i(world.width / 2, world.height / 2)
	if not world.towns.is_empty(): cell = Vector2i(world.towns[0].x, world.towns[0].y)
	go_to_cell(cell, false)

func go_to_cell(cell: Vector2i, reset_zoom: bool = true) -> void:
	if not world.inside(cell): return
	camera_origin = WorldState.chunk_of(cell) * WorldState.CHUNK_SIZE
	offset = size * 0.5 - Vector2(cell - camera_origin) * TILE * zoom
	if reset_zoom:
		zoom = 1.0
		offset = size * 0.5 - Vector2(cell - camera_origin) * TILE * zoom
	person_positions.clear()
	effects.clear()
	hover = WorldState.NO_CELL
	last_painted = WorldState.NO_CELL
	queue_redraw()

func cell_to_local(cell: Vector2i) -> Vector2:
	return offset + (Vector2(cell - camera_origin) + Vector2.ONE * 0.5) * TILE * zoom

func zoom_by(factor: float) -> void:
	if world != null:
		_zoom_at(size * 0.5, factor)

func rebuild_texture() -> void:
	texture_dirty = false
	minimap_bounds = world.land_bounds()
	if not show_minimap:
		texture = null
		queue_redraw()
		return
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(COLORS[0])
	var ratio := Vector2.ONE * 128 / Vector2(minimap_bounds.size)
	for coord in world.region_keys():
		var rect := Rect2i(Vector2(coord * WorldState.CHUNK_SIZE - minimap_bounds.position) * ratio, Vector2.ONE * WorldState.CHUNK_SIZE * ratio)
		if rect.size.x > 2 and rect.size.y > 2:
			for y in WorldState.CHUNK_SIZE:
				for x in WorldState.CHUNK_SIZE:
					var cell: Vector2i = coord * WorldState.CHUNK_SIZE + Vector2i(x, y)
					var point := Vector2i(Vector2(cell - minimap_bounds.position) * ratio)
					image.fill_rect(Rect2i(point, Vector2i(maxi(1, ceili(ratio.x)), maxi(1, ceili(ratio.y)))), COLORS[world.terrain_at(cell)])
		else:
			image.fill_rect(Rect2i(rect.position, Vector2i(maxi(1, rect.size.x), maxi(1, rect.size.y))), COLORS[WorldState.Terrain.GRASS])
	texture = ImageTexture.create_from_image(image)
	queue_redraw()

func _chunk_texture(coord: Vector2i, detailed: bool) -> ImageTexture:
	var cache: Dictionary = chunk_textures if detailed else overview_textures
	var current_revision: int = world.revisions.get(coord, 0)
	cache_clock += 1
	if cache.has(coord) and cache[coord].revision == current_revision:
		cache[coord].used = cache_clock
		return cache[coord].image
	var request := Vector3i(coord.x, coord.y, 1 if detailed else 0)
	if not bake_pending.has(request) and bake_queue.size() < CACHE_LIMIT * 2:
		bake_pending[request] = true
		bake_queue.append({"coord":coord,"detailed":detailed,"request":request})
	return cache[coord].image if cache.has(coord) else null

func _advance_baking() -> void:
	if bake_job == null and not bake_queue.is_empty():
		var nearest := 0
		var center := Vector2(local_to_cell(size * .5)) / WorldState.CHUNK_SIZE
		var best := INF
		for i in bake_queue.size():
			var distance := Vector2(bake_queue[i].coord).distance_squared_to(center) - (1000000.0 if not bake_queue[i].detailed else 0.0)
			if distance < best: best = distance; nearest = i
		var request: Dictionary = bake_queue[nearest]
		bake_queue.remove_at(nearest)
		bake_job = WorldChunkBakeJob.new(world, request.coord, request.detailed)
	if bake_job == null: return
	if not bake_job.advance(1500): return
	var job := bake_job
	bake_job = null
	bake_pending.erase(Vector3i(job.coord.x, job.coord.y, 1 if job.detailed else 0))
	if job.revision != int(world.revisions.get(job.coord, 0)): return
	var cache := chunk_textures if job.detailed else overview_textures
	cache_clock += 1
	cache[job.coord] = {"image":job.texture,"revision":job.revision,"used":cache_clock,"shores":job.shores}
	if cache.size() > CACHE_LIMIT:
		var oldest: Vector2i = job.coord
		for key in cache:
			if cache[key].used < cache[oldest].used: oldest = key
		cache.erase(oldest)

func _draw_regions() -> void:
	var low := WorldState.chunk_of(local_to_cell(Vector2.ZERO))
	var high := WorldState.chunk_of(local_to_cell(size))
	var detailed := zoom * get_window().content_scale_factor >= 0.5 and (high.x - low.x + 1) * (high.y - low.y + 1) <= CACHE_LIMIT - 8
	var candidates := {}
	if detailed:
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var coord := Vector2i(x, y)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if world.has_region(coord + Vector2i(dx, dy)): candidates[coord] = true
	else:
		for key in world.region_bounds: candidates[key] = true
	for key in candidates:
		if key.x < low.x or key.y < low.y or key.x > high.x or key.y > high.y: continue
		var corner := Vector2(key * WorldState.CHUNK_SIZE - camera_origin) * TILE
		var rect := Rect2(offset + corner * zoom, Vector2.ONE * WorldState.CHUNK_SIZE * TILE * zoom)
		if not detailed and rect.size.x < 2:
			draw_circle(rect.get_center(), 1.5, Color("a2bd78"))
			continue
		var region_texture := _chunk_texture(key, detailed)
		if region_texture == null:
			var preview := _chunk_texture(key, false) if detailed else null
			if preview != null: draw_texture_rect(preview,rect,false)
			continue
		if detailed:
			draw_texture_rect_region(region_texture, rect, Rect2(Vector2.ONE * HALO * TILE, Vector2.ONE * WorldState.CHUNK_SIZE * TILE))
		else:
			draw_texture_rect(region_texture, rect, false)
		if detailed:
			for shore in chunk_textures[key].shores:
				var alpha := 0.1 + (sin(visual_time * 1.4 + shore.x * 0.5 + shore.y) + 1.0) * 0.12
				var point := offset + (Vector2(shore - camera_origin) * TILE + Vector2(2, 3)) * zoom
				draw_line(point, point + Vector2(4, 0) * zoom, Color(0.82, 0.93, 0.79, alpha), zoom)

	for key in overview_textures.keys():
		if not world.has_region(key): overview_textures.erase(key)

func _make_chunk_texture(coord: Vector2i) -> ImageTexture:
	var job := WorldChunkBakeJob.new(world, coord, true)
	job.advance(0)
	baking_shores = job.shores
	return job.texture

func _process(delta: float) -> void:
	_advance_baking()
	if texture_dirty:
		rebuild_texture()
	if not reduce_motion:
		visual_time += delta
	for i in range(effects.size() - 1, -1, -1):
		effects[i].age += delta
		if effects[i].age >= effects[i].duration:
			effects.remove_at(i)
	if world != null:
		var live_ids := {}
		_refresh_visible_people()
		for p in visible_people:
			live_ids[p.id] = true
			var target := Vector2(Vector2i(p.x, p.y) - camera_origin) * TILE + Vector2(4, 4)
			var current: Vector2 = person_positions.get(p.id, target)
			var movement := target - current
			if absf(movement.x) > 0.1:
				person_directions[p.id] = signf(movement.x)
			person_positions[p.id] = current.lerp(target, 1.0 - exp(-delta * 16.0)) if not reduce_motion else target
		for id in person_positions.keys():
			if not live_ids.has(id):
				person_positions.erase(id)
				person_directions.erase(id)
	queue_redraw()

func _invalidate_texture() -> void:
	texture_dirty = true
	population_view_signature.clear()

func _invalidate_population_view() -> void:
	population_view_signature.clear()

func _refresh_visible_people() -> void:
	var signature := [world.ticks, world.revision, world.people.size(), camera_origin, offset, zoom, size]
	if signature == population_view_signature: return
	population_view_signature = signature
	visible_people.clear()
	if zoom < 0.15: return
	var viewport := Rect2(Vector2.ZERO, size).grow(60)
	for member in world.people:
		if not WorldMaritime.onboard(world, member.id) and viewport.has_point(cell_to_local(Vector2i(member.x, member.y))): visible_people.append(member)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLORS[0])
	if world == null:
		return
	_draw_regions()
	draw_set_transform(offset, 0, Vector2.ONE * zoom)
	for town in world.towns:
		if not Rect2(Vector2.ZERO, size).grow(60).has_point(cell_to_local(Vector2i(town.x, town.y))): continue
		var pos := Vector2(Vector2i(town.x, town.y) - camera_origin) * TILE
		if zoom < 0.15:
			draw_circle(pos + Vector2(4, 4), 3.5 / zoom, Color("f2c879"))
			continue

		draw_rect(Rect2(pos + Vector2(6, -10), Vector2(1, 18)), Color("f1dfb2"))
		var flutter := sin(visual_time * 3.0 + town.id) * 1.2
		draw_rect(Rect2(pos + Vector2(7, -10 + flutter), Vector2(7, 4)), Color("f2c879"))
	if zoom >= 0.15:
		for value in world.buildings: _draw_building(value)
	_refresh_visible_people()
	for p in visible_people:
		if WorldMaritime.onboard(world, p.id): continue
		if zoom < 0.15 or not Rect2(Vector2.ZERO, size).grow(30).has_point(cell_to_local(Vector2i(p.x, p.y))): continue
		var target := Vector2(Vector2i(p.x, p.y) - camera_origin) * TILE + Vector2(4, 4)
		var pos: Vector2 = person_positions.get(p.id, target)
		var walking := pos.distance_to(target) > 0.2
		var bob := -absf(sin(visual_time * 14.0 + p.id)) * 0.8 if walking and not reduce_motion else 0.0
		var scale_value := maxf(0.85, 0.7 / zoom)
		var life_stage: int = WorldLife.stage(world, p)
		if life_stage < 3: scale_value *= [0.5, 0.65, 0.8][life_stage]
		var sprite: ImageTexture = job_textures.get(p.job, person_texture) if p.hunger < 60 else alert_texture
		var rect := Rect2(pos + Vector2(-4, -10 + bob) * scale_value, Vector2(8, 12) * scale_value)
		if person_directions.get(p.id, 1.0) < 0:
			rect.position.x += rect.size.x
			rect.size.x *= -1
		draw_texture_rect(sprite, rect, false)
		if life_stage == 5:
			draw_rect(Rect2(pos + Vector2(-2, -9 + bob) * scale_value, Vector2(4, 2) * scale_value), Color("e3dfcc"))
		if p.cargo > 0:
			var cargo_color := Color("956945") if p.cargo_kind == "wood" else Color("e6c879")
			draw_rect(Rect2(pos + Vector2(3, -5) * scale_value, Vector2(4, 4) * scale_value), Color("334c40"))
			draw_rect(Rect2(pos + Vector2(4, -5) * scale_value, Vector2(3, 3) * scale_value), cargo_color)
	for key in world.fires:
		if not Rect2(Vector2.ZERO, size).grow(30).has_point(cell_to_local(key)): continue
		var index := hash(key) % 10000
		var pos := Vector2(key - camera_origin) * TILE
		var flicker := sin(visual_time * 12.0 + index) * 1.5
		draw_circle(pos + Vector2(4, 4), 9, Color(1, 0.57, 0.2, 0.13))
		draw_rect(Rect2(pos + Vector2(1, 2), Vector2(6, 6)), Color("db6943"))
		draw_rect(Rect2(pos + Vector2(3, -1 + flicker), Vector2(3, 7)), Color("f5b65b"))
		draw_rect(Rect2(pos + Vector2(3, 4), Vector2(2, 3)), Color("ffe6a0"))
		var rise := fmod(visual_time * 8.0 + index * 0.7, 18.0)
		draw_rect(Rect2(pos + Vector2(2 + sin(index + visual_time), -rise), Vector2(3, 3)), Color(0.29, 0.35, 0.31, (1.0 - rise / 18.0) * 0.4))
	_draw_effects()
	for ship in world.voyages:
		var cell := WorldMaritime.position(ship)
		if not Rect2(Vector2.ZERO, size).grow(50).has_point(cell_to_local(cell)): continue
		var pos := Vector2(cell - camera_origin) * TILE
		if zoom < 0.15:
			draw_circle(pos + Vector2(4, 4), 3 / zoom, Color("9bd2db"))
		else:
			draw_texture_rect(vessel_textures[ship.kind], Rect2(pos + Vector2(-6, -16), Vector2(24, 24)), false)
	if interface_visible and world.inside(selected):
		var select_rect := Rect2(Vector2(selected - camera_origin) * TILE, Vector2.ONE * TILE).grow(2)
		draw_rect(select_rect, Color(1.0, 0.9, 0.65, 0.15))
		draw_rect(select_rect, Color("ffe6ac"), false, 1.3 / zoom)
	if interface_visible and world.inside(hover) and tool != "pan":
		_draw_brush()
	draw_set_transform(Vector2.ZERO)
	if interface_visible:
		_draw_labels()
		_draw_minimap()

func _draw_building(value: Dictionary) -> void:
	var cell := Vector2i(value.x, value.y)
	if not Rect2(Vector2.ZERO, size).grow(64).has_point(cell_to_local(cell)): return
	var pos := Vector2(cell - camera_origin) * TILE
	var extent := Vector2.ONE * int(WorldEconomy.SIZE[value.kind]) * TILE
	if not value.ready:
		draw_rect(Rect2(pos, extent), Color("b5a179"))
		draw_rect(Rect2(pos, extent), Color("e1c79a"), false, 1)
		for x in range(0, int(extent.x), 5): draw_rect(Rect2(pos + Vector2(x, 2), Vector2(2, extent.y - 4)), Color("80694f"))
		var progress: float = (value.work + value.delivered) / float(WorldEconomy.WORK[value.kind] + WorldEconomy.COST[value.kind])
		draw_rect(Rect2(pos + Vector2(0, extent.y + 2), Vector2(extent.x, 2)), Color("46574a"))
		draw_rect(Rect2(pos + Vector2(0, extent.y + 2), Vector2(extent.x * progress, 2)), Color("edcc8b"))
		return
	if value.kind == "farm":
		draw_rect(Rect2(pos, extent), Color("78624c"))
		draw_rect(Rect2(pos, extent), Color("b4a16e"), false, 1)
		for row in 5:
			var y := 2 + row * 4
			draw_line(pos + Vector2(2, y), pos + Vector2(extent.x - 3, y), Color("514f3d"), 1)
			if not value.planted and value.stock == 0: continue
			var crop := Color("e1cd7e") if value.stock > 0 else (Color("b6c578") if value.growth > 30 else Color("7f9e60"))
			var height := 3 if value.stock > 0 or value.growth > 30 else 1
			for column in 5:
				draw_rect(Rect2(pos + Vector2(3 + column * 4, y - height), Vector2(2, height)), crop)
		return
	var sprite := house_texture
	if value.kind == "camp": sprite = camp_texture
	elif value.kind == "store": sprite = store_texture
	elif value.kind == "workshop": sprite = workshop_texture
	elif value.kind == "archive": sprite = archive_texture
	elif industry_textures.has(value.kind): sprite = industry_textures[value.kind]
	draw_rect(Rect2(pos + Vector2(-2, 1), extent + Vector2(4, 3)), Color("bdad84"))
	var sprite_size := Vector2(sprite.get_width(), sprite.get_height())
	var corner := pos + Vector2((extent.x - sprite_size.x) * 0.5, extent.y - sprite_size.y)
	draw_texture_rect(sprite, Rect2(corner, sprite_size), false)

func _draw_brush() -> void:
	var radius := mini(brush_radius, 8) if tool == "fire" else (mini(brush_radius, 8) + 3 if tool == "rain" else (brush_radius if tool.begins_with("biome_") or tool in ["water", "sand", "grass", "forest", "mountain"] else 0))
	var color: Color = TOOL_COLORS.get(tool, Color("e8ba83"))
	if tool == "person" and not world.walkable(hover):
		color = Color("ed9376")
	if tool not in ["inspect", "pan"] and radius <= 12:
		for cell in world.cells_in_brush(hover, radius):
			draw_rect(Rect2(Vector2(cell - camera_origin) * TILE, Vector2.ONE * TILE), Color(color, 0.2))
	var center := (Vector2(hover - camera_origin) + Vector2.ONE * 0.5) * TILE
	draw_arc(center, (radius + 0.65) * TILE, 0, TAU, 48, Color(color, 0.9), 1.3 / zoom)
	draw_line(center - Vector2(3, 0), center + Vector2(3, 0), Color(color, 0.9), 1.0 / zoom)
	draw_line(center - Vector2(0, 3), center + Vector2(0, 3), Color(color, 0.9), 1.0 / zoom)

func _draw_effects() -> void:
	for effect in effects:
		var t: float = effect.age / effect.duration
		var center: Vector2 = effect.pos
		var color: Color = effect.color
		var radius: float = effect.radius
		if effect.kind == "rain":
			for drop in 16:
				var angle := drop * 2.399
				var distance := sqrt(float(drop) / 16.0) * radius
				var pos := center + Vector2(cos(angle), sin(angle)) * distance
				pos.y += fmod(t * 26 + drop * 3, 16) - 8
				draw_line(pos, pos + Vector2(-2, 5), Color(color, (1.0 - t) * 0.8), 1.5 / zoom)
		elif effect.kind == "fire":
			if t < 0.18:
				var lightning := PackedVector2Array([center + Vector2(7, -64), center + Vector2(-5, -35), center + Vector2(4, -35), center])
				draw_polyline(lightning, Color("fff0c6"), 3.0 / zoom)
				draw_circle(center, (1.0 - t * 5.0) * 16.0, Color(1.0, 0.89, 0.6, 0.25))
		else:
			for spark in 6:
				var angle := spark * TAU / 6.0
				var pos := center + Vector2(cos(angle), sin(angle)) * t * radius
				draw_rect(Rect2(pos, Vector2.ONE * 2.0 / zoom), Color(color, 1.0 - t))
		draw_arc(center, radius * (0.45 + t * 0.65), 0, TAU, 40, Color(color, (1.0 - t) * 0.7), 1.2 / zoom)

func _draw_labels() -> void:
	if label_font == null:
		return
	for town in world.towns:
		var pos := offset + (Vector2(Vector2i(town.x, town.y) - camera_origin) * TILE + Vector2(4, -22)) * zoom
		var text_value: String = town.name
		var label_size := label_font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var rect := Rect2(pos - Vector2(label_size.x * 0.5 + 7, 15), label_size + Vector2(14, 6))
		if not Rect2(Vector2.ZERO, size).encloses(rect):
			continue
		draw_style_box(_name_style(), rect)
		draw_string(label_font, rect.position + Vector2(7, 13), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f4e5bc"))

func _name_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.2, 0.92)
	style.set_corner_radius_all(4)
	return style

func _draw_minimap() -> void:
	if texture == null or not show_minimap or size.x < 450 or size.y < 330:
		return
	var rect := Rect2(size - Vector2(112, 170), Vector2(88, 88))
	draw_rect(rect.grow(5), Color("252934"))
	draw_texture_rect(texture, rect, false, Color(1, 1, 1, 0.86))
	var ratio := rect.size / (Vector2(minimap_bounds.size) * TILE)
	var visible_rect := Rect2(rect.position + (Vector2(camera_origin - minimap_bounds.position) * TILE - offset / zoom) * ratio, size / zoom * ratio)
	visible_rect = visible_rect.intersection(rect)
	if visible_rect.has_area():
		draw_rect(visible_rect, Color("f3deb0"), false, 1)
	draw_rect(rect.grow(5), Color("9a795f"), false, 1)

func add_effect(cell: Vector2i, kind: String) -> void:
	if kind in ["water", "sand", "grass", "forest", "mountain"] and visual_time - last_effect_time < 0.07:
		return
	last_effect_time = visual_time
	if effects.size() >= 24:
		effects.pop_front()
	effects.append({"pos": (Vector2(cell - camera_origin) + Vector2.ONE * 0.5) * TILE, "kind": kind,
		"color": TOOL_COLORS.get(kind, Color("f5dfaa")), "age": 0.0,
		"duration": 1.1 if kind == "rain" else 0.5,
		"radius": float((mini(brush_radius, 8) + 3 if kind == "rain" else (mini(brush_radius, 8) + 1 if kind == "fire" else brush_radius + 1)) * TILE)})

func local_to_cell(pos: Vector2) -> Vector2i:
	var relative := (pos - offset) / (TILE * zoom)
	return camera_origin + Vector2i(floori(relative.x), floori(relative.y))

func _zoom_at(pos: Vector2, factor: float) -> void:
	var before := (pos - offset) / zoom
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	offset = pos - before * zoom
	_clamp_camera()
	queue_redraw()

func _clamp_camera() -> void:
	var original_center := local_to_cell(size * 0.5)
	var center := original_center
	center = Vector2i(clampi(center.x, -WorldState.COORD_LIMIT, WorldState.COORD_LIMIT - 1), clampi(center.y, -WorldState.COORD_LIMIT, WorldState.COORD_LIMIT - 1))
	offset += Vector2(original_center - center) * TILE * zoom
	var new_origin := WorldState.chunk_of(center) * WorldState.CHUNK_SIZE
	if new_origin == camera_origin: return
	var shift := Vector2(new_origin - camera_origin) * TILE
	offset += shift * zoom
	for id in person_positions: person_positions[id] -= shift
	for effect in effects: effect.pos -= shift
	camera_origin = new_origin

func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag): return
	if event is InputEventMouseButton:
		hover = local_to_cell(event.position)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if tool == "pan":
				panning = event.pressed
			else:
				dragging = event.pressed
				last_painted = WorldState.NO_CELL
				if event.pressed:
					apply_tool(hover)
	elif event is InputEventMouseMotion:
		hover = local_to_cell(event.position)
		if panning:
			offset += event.relative
			_clamp_camera()
		elif dragging and (tool.begins_with("biome_") or tool in ["water", "sand", "grass", "forest", "mountain"]):
			_paint_segment(last_painted, hover)
	elif event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			last_touch = event.position
			if touches.size() == 1:
				touch_painted = false
				last_painted = WorldState.NO_CELL
			if touches.size() == 2:
				touch_painted = true
				pinch_distance = _touch_distance()
		else:
			if touches.size() == 1 and not touch_painted and tool != "pan":
				apply_tool(local_to_cell(event.position))
			touches.erase(event.index)
			pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		var previous: Vector2 = touches[event.index]
		touches[event.index] = event.position
		if touches.size() >= 2:
			var distance := _touch_distance()
			var center: Vector2 = (touches.values()[0] + touches.values()[1]) * 0.5
			if pinch_distance > 0:
				_zoom_at(center, distance / pinch_distance)
			pinch_distance = distance
			touch_painted = true
		elif tool == "pan" or tool == "inspect":
			if not touch_painted and event.position.distance_to(last_touch) < 10: return
			offset += event.position - previous
			_clamp_camera()
			touch_painted = true
		elif tool.begins_with("biome_") or tool in ["water", "sand", "grass", "forest", "mountain"]:
			_paint_segment(local_to_cell(previous), local_to_cell(event.position))
			touch_painted = true
	queue_redraw()
	accept_event()

func _touch_distance() -> float:
	var positions := touches.values()
	return positions[0].distance_to(positions[1])

func _paint_segment(start: Vector2i, finish: Vector2i) -> void:
	if start == WorldState.NO_CELL:
		apply_tool(finish)
		return
	var distance := maxi(abs(finish.x - start.x), abs(finish.y - start.y))
	for i in range(1, mini(distance, 128) + 1):
		apply_tool(Vector2i(Vector2(start).lerp(Vector2(finish), float(i) / distance).round()))

func apply_tool(cell: Vector2i) -> void:
	if not world.inside(cell) or cell == last_painted:
		return
	last_painted = cell
	if (world.stepping or edits_locked) and tool != "inspect":
		if pending_tools.size() < 512: pending_tools.append({"cell":cell,"tool":tool,"radius":brush_radius})
		return
	_apply_tool_now(cell)

func flush_tools(budget_usec: int = 2000) -> void:
	if world.stepping or edits_locked: return
	var previous_tool := tool
	var previous_radius := brush_radius
	var deadline := Time.get_ticks_usec() + budget_usec
	while not pending_tools.is_empty():
		var command: Dictionary = pending_tools.pop_front()
		tool = command.tool; brush_radius = command.radius
		_apply_tool_now(command.cell)
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	tool = previous_tool; brush_radius = previous_radius

func _apply_tool_now(cell: Vector2i) -> void:
	if tool.begins_with("biome_"):
		if not WorldClimate.paint(world,cell,brush_radius,int(tool.trim_prefix("biome_"))): feedback.emit("Достигнут лимит ручных биомов. Используйте климатические пояса.")
		return
	match tool:
		"inspect":
			selected = cell
			cell_selected.emit(cell)
		"water", "sand", "grass", "forest", "mountain":
			var terrain: int = {"water": 0, "sand": 1, "grass": 2, "forest": 3, "mountain": 4}[tool]
			if world.paint(cell, brush_radius, terrain):
				add_effect(cell, tool)
			else: feedback.emit("Достигнут лимит участков (%d). Удалите ненужную сушу водой." % WorldState.MAX_CHUNKS)
		"person":
			if world.add_person(cell):
				add_effect(cell, tool)
			else:
				feedback.emit("Жителям нужна равнина, лес или песок. Лимит: %d." % WorldState.MAX_PEOPLE)
		"fire":
			world.ignite(cell, mini(brush_radius, 8))
			add_effect(cell, tool)
		"rain":
			world.rain(cell, mini(brush_radius, 8) + 3)
			add_effect(cell, tool)
