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
var brush_job: WorldBrushJob
var terrain_repair_job: WorldTerrainRepairJob
var stroke_coverage: Dictionary = {}
var stroke_signature: Array = []
var brush_touched: Dictionary = {}
var brush_terrain_dirty := false
var brush_changed := false
var brush_repair_needed := false
var brush_repair_checked := false
var brush_usec := 0
var brush_cells_written := 0
var brush_masks: Dictionary = {}
var brush_previews: Dictionary = {}
var last_brush_input_usec := 0
var bake_job: WorldChunkBakeJob
var bake_queue: Array[Dictionary] = []
var bake_pending: Dictionary = {}
var drawn_textures: Array[Texture2D] = []
var season_material: ShaderMaterial
var visual_season := -1
var minimap_job: WorldMinimapBakeJob
var minimap_revision := -1
var name_style: StyleBoxFlat
var people_multimesh: MultiMesh
var ornaments_multimesh: MultiMesh
var fire_multimesh: MultiMesh
var fire_atlas: ImageTexture
var fire_mesh_job: WorldFireMeshJob
var fire_view_signature: Array = []
var fire_job_signature: Array = []
var people_atlas: ImageTexture
var atlas_jobs: Dictionary = {}
var people_buffer := PackedFloat32Array()
var ornaments_buffer := PackedFloat32Array()
var live_visible_ids: Dictionary = {}
var draw_usec := 0
var process_usec := 0
var visible_regions: Array[Vector2i] = []
var region_view_signature: Array = []
var visible_shores: Array[Vector2i] = []
var population_view_epoch := 0
var population_index_job: WorldPopulationRebuildJob
var mesh_dirty := true
var people_animating := false
var render_ids := PackedInt32Array()
var render_targets := PackedVector2Array()
var render_scales := PackedFloat32Array()
var render_sprites := PackedInt32Array()
var render_elder := PackedByteArray()
var render_cargo := PackedByteArray()
var render_hunger := PackedByteArray()
var render_palettes := PackedByteArray()
var person_outfits := {}
var appearance_job: WorldAppearanceJob
var appearance_dirty := true
var town_appearances := {}
var working_buildings := {}
var appearance_candidates := {}
var house_variants := {}
var settlement_marks := {}
var supplies_textures := {}
var idle_furnaces := {}
var appearance_usec := 0
var appearance_builds := 0
var weather_strikes := {}
const JOB_SKILLS := WorldAppearanceJob.JOB_SKILLS

func _ready() -> void:
	season_material = ShaderMaterial.new()
	season_material.shader = preload("res://assets/terrain_seasons.gdshader")
	material = season_material
	name_style = _name_style()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	house_texture = PixelArt.sprite_texture(PixelArt.HOUSE)
	camp_texture = PixelArt.sprite_texture(PixelArt.CAMP)
	store_texture = PixelArt.sprite_texture(PixelArt.STORE)
	workshop_texture = PixelArt.sprite_texture(PixelArt.WORKSHOP)
	archive_texture = PixelArt.sprite_texture(PixelArt.ARCHIVE)
	for kind in ["kiln","loom","forge","market","school","council","dock","port","boat","sailboat"]: industry_textures[kind]=PixelArt.building_texture(kind)
	vessel_textures = {"boat": PixelArt.vessel_texture(false), "sailboat": PixelArt.vessel_texture(true)}
	for job in PixelArt.JOB_COLORS:
		for cold in [false, true]:
			for master in [false, true]:
				job_textures[_outfit_key(job, master, cold)] = ImageTexture.create_from_image(PixelArt.person_image(job, master, cold))
	person_texture = ImageTexture.create_from_image(PixelArt.person_image("settler"))
	alert_texture = person_texture
	for domain in WorldAppearanceJob.COLORS:
		house_variants[domain] = PixelArt.house_variant(domain)
		for form in 3: house_variants[domain + ":" + str(form)] = PixelArt.house_variant(domain, form)
		settlement_marks[domain] = PixelArt.settlement_mark(domain)
	for domain in ["food", "materials", "maritime", "trade"]: supplies_textures[domain] = PixelArt.supplies_texture(domain)
	for kind in ["forge", "kiln"]: idle_furnaces[kind] = PixelArt.idle_furnace(kind)
	_prepare_people_meshes()
	_prepare_fire_mesh()
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
	if fire_multimesh != null: fire_multimesh.visible_instance_count = 0
	fire_mesh_job = null; fire_view_signature.clear(); fire_job_signature.clear()
	person_positions.clear()
	person_directions.clear()
	person_outfits.clear()
	appearance_job = null; appearance_dirty = true
	town_appearances.clear(); working_buildings.clear(); appearance_candidates.clear()
	visible_people.clear(); population_view_signature.clear()
	population_index_job = null
	visible_regions.clear(); region_view_signature.clear(); visible_shores.clear()
	if people_multimesh != null: people_multimesh.visible_instance_count = 0; ornaments_multimesh.visible_instance_count = 0
	effects.clear()
	weather_strikes.clear()
	camera_origin = Vector2i.ZERO
	chunk_textures.clear()
	overview_textures.clear()
	bake_job = null; bake_queue.clear(); bake_pending.clear()
	minimap_job = null; minimap_revision = -1; visual_season = -1
	pending_tools.clear()
	brush_job = null; terrain_repair_job = null; brush_touched.clear()
	brush_previews.clear()
	brush_terrain_dirty = false; brush_changed = false; stroke_coverage = {}; stroke_signature.clear()
	brush_repair_needed = false
	brush_repair_checked = false
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
	if not show_minimap:
		texture = null
		minimap_job = null
		return
	if minimap_job == null and minimap_revision != world.revision:
		minimap_job = WorldMinimapBakeJob.new(world)

func _advance_minimap() -> void:
	if minimap_job == null: return
	if not minimap_job.advance(500): return
	minimap_bounds = minimap_job.bounds
	if texture == null: texture = ImageTexture.create_from_image(minimap_job.image)
	else: texture.update(minimap_job.image)
	minimap_revision = minimap_job.revision
	minimap_job = null
	texture_dirty = minimap_revision != world.revision

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
	var cache := chunk_textures if job.detailed else overview_textures
	if cache.has(job.coord) and int(cache[job.coord].revision) > job.revision: return
	cache_clock += 1
	var ready_texture: ImageTexture
	if cache.has(job.coord):
		ready_texture = cache[job.coord].image
		ready_texture.update(job.image)
	else: ready_texture = ImageTexture.create_from_image(job.image)
	cache[job.coord] = {"image":ready_texture,"revision":job.revision,"used":cache_clock,"shores":job.shores}
	if job.detailed and brush_previews.has(job.coord) and job.revision >= int(brush_previews[job.coord].revision): brush_previews.erase(job.coord)
	if cache.size() > CACHE_LIMIT:
		var oldest: Vector2i = job.coord
		for key in cache:
			if cache[key].used < cache[oldest].used: oldest = key
		cache.erase(oldest)

func _draw_regions() -> void:
	var low := WorldState.chunk_of(local_to_cell(Vector2.ZERO))
	var high := WorldState.chunk_of(local_to_cell(size))
	var detailed := zoom * get_window().content_scale_factor >= 0.5 and (high.x - low.x + 1) * (high.y - low.y + 1) <= CACHE_LIMIT - 8
	var signature := [low, high, detailed, world.revision, world.region_count()]
	if signature != region_view_signature:
		region_view_signature = signature
		visible_regions.clear()
		if detailed:
			for y in range(low.y, high.y + 1):
				for x in range(low.x, high.x + 1):
					var coord := Vector2i(x, y)
					var exists := false
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							if world.has_region(coord + Vector2i(dx, dy)): exists = true; break
						if exists: break
					if exists: visible_regions.append(coord)
		else:
			for key in world.region_bounds:
				if key.x >= low.x and key.y >= low.y and key.x <= high.x and key.y <= high.y and world.has_region(key): visible_regions.append(key)
	visible_shores.clear()
	for key in visible_regions:
		var corner := Vector2(key * WorldState.CHUNK_SIZE - camera_origin) * TILE
		var rect := Rect2(offset + corner * zoom, Vector2.ONE * WorldState.CHUNK_SIZE * TILE * zoom)
		if not detailed and rect.size.x < 2:
			draw_circle(rect.get_center(), 1.5, Color("a2bd78"))
			continue
		var region_texture := _chunk_texture(key, detailed)
		if region_texture == null:
			var preview := _chunk_texture(key, false) if detailed else null
			if preview != null:
				drawn_textures.append(preview)
				draw_texture_rect(preview,rect,false)
			elif not detailed and chunk_textures.has(key):
				var close_texture: ImageTexture = chunk_textures[key].image
				drawn_textures.append(close_texture)
				draw_texture_rect_region(close_texture, rect, Rect2(Vector2.ONE * HALO * TILE, Vector2.ONE * WorldState.CHUNK_SIZE * TILE))
			continue
		drawn_textures.append(region_texture)
		if detailed:
			draw_texture_rect_region(region_texture, rect, Rect2(Vector2.ONE * HALO * TILE, Vector2.ONE * WorldState.CHUNK_SIZE * TILE))
		else:
			draw_texture_rect(region_texture, rect, false)
		if detailed: visible_shores.append_array(chunk_textures[key].shores)
	for shore in visible_shores:
		var alpha := 0.1 + (sin(visual_time * 1.4 + shore.x * 0.5 + shore.y) + 1.0) * 0.12
		var point := offset + (Vector2(shore - camera_origin) * TILE + Vector2(2, 2.5)) * zoom
		draw_rect(Rect2(point, Vector2(4, 1) * zoom), Color(0.82, 0.93, 0.79, alpha))
	for key in brush_previews:
		var patch: Dictionary = brush_previews[key]
		if patch.texture == null: continue
		var rect := Rect2(offset+Vector2(key*WorldState.CHUNK_SIZE-camera_origin)*TILE*zoom,Vector2.ONE*WorldState.CHUNK_SIZE*TILE*zoom)
		if not rect.intersects(Rect2(Vector2.ZERO,size)): continue
		drawn_textures.append(patch.texture)
		draw_texture_rect(patch.texture,rect,false)

	for key in overview_textures.keys():
		if not world.has_region(key): overview_textures.erase(key)

func _make_chunk_texture(coord: Vector2i) -> ImageTexture:
	var job := WorldChunkBakeJob.new(world, coord, true)
	job.advance(0)
	baking_shores = job.shores
	return ImageTexture.create_from_image(job.image)

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	if world == null: return
	var season := WorldClimate.season(world) if world.climate.seasons else 1
	if season != visual_season:
		visual_season = season
		season_material.set_shader_parameter("autumn_amount", 0.25 if season == 2 else 0.0)
		season_material.set_shader_parameter("winter_amount", 0.55 if season == 3 else 0.0)
		population_view_signature.clear()
	world.reclaim_navigation()
	_advance_population_index()
	_update_brush_previews()
	_advance_baking()
	_advance_minimap()
	if texture_dirty:
		rebuild_texture()
	if not reduce_motion:
		visual_time += delta
	for i in range(effects.size() - 1, -1, -1):
		effects[i].age += delta
		if effects[i].age >= effects[i].duration:
			effects.remove_at(i)
	_refresh_visible_people()
	_update_people_meshes(delta)
	_advance_appearance()
	_refresh_weather_effects()
	_advance_fire_mesh()
	season_material.set_shader_parameter("fire_time",visual_time)
	queue_redraw()
	process_usec = Time.get_ticks_usec() - started

func _advance_population_index() -> void:
	if world.population.ready: population_index_job = null; return
	if world.stepping: return
	if population_index_job == null: population_index_job = WorldPopulationRebuildJob.new(world)
	var deadline := Time.get_ticks_usec()+300
	while not population_index_job.finished:
		population_index_job.unit()
		if Time.get_ticks_usec() >= deadline: return
	population_index_job = null

func _update_brush_previews() -> void:
	var retired := WorldState.NO_CELL
	for key in brush_previews:
		var patch: Dictionary = brush_previews[key]
		if patch.dirty:
			if patch.texture == null: patch.texture = ImageTexture.create_from_image(patch.pixels)
			else: patch.texture.update(patch.pixels)
			patch.dirty = false
		if brush_previews.size() > CACHE_LIMIT*2 and not Rect2(offset+Vector2(key*WorldState.CHUNK_SIZE-camera_origin)*TILE*zoom,Vector2.ONE*WorldState.CHUNK_SIZE*TILE*zoom).intersects(Rect2(Vector2.ZERO,size)): retired = key
	if retired != WorldState.NO_CELL: brush_previews.erase(retired)

func _invalidate_texture() -> void:
	texture_dirty = true

func _invalidate_population_view() -> void:
	population_view_epoch += 1
	population_view_signature.clear()
	appearance_dirty = true

func _advance_appearance() -> void:
	var started := Time.get_ticks_usec()
	if appearance_job == null:
		if not appearance_dirty: appearance_usec = 0; return
		appearance_job = WorldAppearanceJob.new(world, person_outfits, town_appearances, appearance_candidates)
		appearance_dirty = false
	if appearance_job.advance(200):
		town_appearances = appearance_job.towns
		working_buildings = appearance_job.working
		appearance_job = null
		appearance_builds += 1
	appearance_usec = Time.get_ticks_usec() - started

func _outfit_key(job: String, master: bool, cold: bool) -> String:
	return job + (":master" if master else "") + (":cold" if cold else "")

func _person_outfit(member: Dictionary, life_stage: int) -> int:
	var job: String = member.job
	if not PixelArt.JOB_COLORS.has(job): job = "settler"
	var previous: Dictionary = person_outfits.get(member.id, {})
	if life_stage < 3:
		job = "child" if life_stage < 2 else "teen"
		person_outfits.erase(member.id)
	else:
		if previous.is_empty(): previous = {"job": job, "candidate": job, "since": world.ticks}
		if job == "settler" and previous.job not in ["child", "teen", "carer"]: job = previous.job
		if previous.candidate != job: previous.candidate = job; previous.since = world.ticks
		if world.ticks - int(previous.since) >= 3: previous.job = job
		person_outfits[int(member.id)] = previous
		job = previous.job
	var master := life_stage >= 3 and JOB_SKILLS.has(job) and WorldSocial.level(member, JOB_SKILLS[job]) == 3
	var cold: bool = (world.climate.seasons and visual_season == 3) or WorldWeather.at(world, Vector2i(member.x, member.y), "frost")
	return atlas_jobs.get(_outfit_key(job, master, cold), atlas_jobs.default)

func _refresh_visible_people() -> void:
	var signature := [population_view_epoch, world.people.size(), camera_origin, offset, zoom, size]
	if signature == population_view_signature: return
	population_view_signature = signature
	visible_people.clear(); live_visible_ids.clear()
	render_ids.clear(); render_targets.clear(); render_scales.clear(); render_sprites.clear(); render_elder.clear(); render_cargo.clear(); render_hunger.clear(); render_palettes.clear()
	mesh_dirty = true
	var base_scale := maxf(0.85, 0.7 / zoom)
	if zoom >= 0.15:
		var viewport := Rect2(Vector2.ZERO, size).grow(60)
		for member in _render_candidates(viewport):
			if not WorldMaritime.onboard(world, member.id) and viewport.has_point(cell_to_local(Vector2i(member.x, member.y))):
				visible_people.append(member); live_visible_ids[member.id] = true
				render_ids.append(int(member.id))
				render_targets.append(Vector2(Vector2i(member.x, member.y) - camera_origin) * TILE + Vector2(4, 4))
				var life_stage := WorldLife.stage(world, member)
				render_scales.append(base_scale * ([0.5, 0.65, 0.8][life_stage] if life_stage < 3 else 1.0))
				render_sprites.append(_person_outfit(member, life_stage))
				render_hunger.append(1 if member.hunger >= 60 else 0)
				render_palettes.append(PixelArt.person_palette(world.world_seed, member.id))
				render_elder.append(1 if life_stage == 5 else 0)
				render_cargo.append(0 if member.cargo == 0 else (1 if member.cargo_kind == "wood" else 2))
	for id in person_positions.keys():
		if not live_visible_ids.has(id): person_positions.erase(id); person_directions.erase(id)

func _render_candidates(viewport: Rect2) -> Array[Dictionary]:
	if not world.population.ready: return world.people
	var low := WorldPopulation.bucket(local_to_cell(viewport.position)-Vector2i.ONE)
	var high := WorldPopulation.bucket(local_to_cell(viewport.end)+Vector2i.ONE)
	if (high.x-low.x+1)*(high.y-low.y+1) >= world.people.size()/4: return world.people
	var ids: Array = []
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			ids.append_array(world.population.cells.get(Vector2i(x,y),[]))
			if ids.size() >= world.people.size()/2: return world.people
	if world.population.monotonic_ids: ids.sort()
	else: ids.sort_custom(func(a: int,b: int): return int(world.population.order[a]) < int(world.population.order[b]))
	var result: Array[Dictionary] = []
	for id in ids:
		var member: Dictionary = world.person_index.get(id,{})
		if not member.is_empty(): result.append(member)
	return result

func _prepare_people_meshes() -> void:
	var atlas := Image.create((job_textures.size() + 2) * 16, 16 * PixelArt.PEOPLE_PALETTES, false, Image.FORMAT_RGBA8)
	var index := 0
	for job in job_textures:
		atlas_jobs[job] = index
		var parts: PackedStringArray = job.split(":")
		for palette in PixelArt.PEOPLE_PALETTES:
			atlas.blit_rect(PixelArt.person_image(parts[0], parts.has("master"), parts.has("cold"), palette), Rect2i(0, 0, 16, 16), Vector2i(index * 16, palette * 16))
		index += 1
	atlas_jobs["default"] = index
	for palette in PixelArt.PEOPLE_PALETTES: atlas.blit_rect(PixelArt.person_image("settler", false, false, palette), Rect2i(0, 0, 16, 16), Vector2i(index * 16, palette * 16))
	index += 1
	atlas_jobs["alert"] = index
	for palette in PixelArt.PEOPLE_PALETTES: atlas.blit_rect(PixelArt.person_image("settler", false, false, palette), Rect2i(0, 0, 16, 16), Vector2i(index * 16, palette * 16))
	people_atlas = ImageTexture.create_from_image(atlas)
	season_material.set_shader_parameter("atlas_columns", float(job_textures.size() + 2))
	season_material.set_shader_parameter("atlas_rows", float(PixelArt.PEOPLE_PALETTES))
	people_multimesh = _multimesh(Vector2(16, 16), WorldState.MAX_PEOPLE, true)
	ornaments_multimesh = _multimesh(Vector2.ONE, WorldState.MAX_PEOPLE * 3, false)
	people_buffer.resize(WorldState.MAX_PEOPLE * 12)
	ornaments_buffer.resize(WorldState.MAX_PEOPLE * 3 * 12)

func _prepare_fire_mesh() -> void:
	var atlas := Image.create(24*4,32,false,Image.FORMAT_RGBA8)
	for frame in 4:
		for y in 24:
			for x in 24:
				var distance := Vector2(x-12,y-23).length()/11.0
				if distance < 1.0: atlas.set_pixel(frame*24+x,y,Color(1,0.57,0.2,(1.0-distance)*0.15))
		var flutter: int = [0,2,1,3][frame]
		atlas.fill_rect(Rect2i(frame*24+9,21,6,6),Color("db6943"))
		atlas.fill_rect(Rect2i(frame*24+11,16-flutter,3,10+flutter),Color("f5b65b"))
		atlas.fill_rect(Rect2i(frame*24+11,23,2,3),Color("ffe6a0"))
		atlas.fill_rect(Rect2i(frame*24+9+frame%2,4+frame*2,3,3),Color(0.29,0.35,0.31,0.22))
	fire_atlas = ImageTexture.create_from_image(atlas)
	fire_multimesh = _multimesh(Vector2(24,32),4096,true)

func _advance_fire_mesh() -> void:
	var low := local_to_cell(Vector2(-30,-30))
	var high := local_to_cell(size+Vector2(30,30))
	var span := maxi(1,ceili(sqrt(float((high.x-low.x+1)*(high.y-low.y+1))/3600.0)))
	var signature := [world.fire_revision,camera_origin,low,high,span]
	if fire_mesh_job != null and (fire_mesh_job.origin != camera_origin or fire_mesh_job.low != low or fire_mesh_job.high != high):
		fire_mesh_job = null; fire_multimesh.visible_instance_count = 0
	if fire_mesh_job == null:
		if signature == fire_view_signature: return
		fire_job_signature = signature
		fire_mesh_job = WorldFireMeshJob.new(world,camera_origin,low,high,span)
	if not fire_mesh_job.advance(500): return
	var count := mini(fire_mesh_job.buffer.size()/12,4096)
	fire_multimesh.visible_instance_count = count
	if count > 0:
		fire_mesh_job.buffer.resize(4096*12)
		fire_multimesh.buffer = fire_mesh_job.buffer
	fire_view_signature = fire_job_signature
	fire_mesh_job = null

func _multimesh(dimensions: Vector2, capacity: int, custom: bool) -> MultiMesh:
	var mesh := QuadMesh.new()
	mesh.size = dimensions
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_2D
	instances.use_custom_data = custom
	instances.use_colors = not custom
	instances.mesh = mesh
	instances.instance_count = capacity
	instances.visible_instance_count = 0
	return instances

func _ornament(index: int, rect: Rect2, color: Color) -> int:
	var base := index * 12
	var center := rect.get_center()
	ornaments_buffer[base] = rect.size.x; ornaments_buffer[base + 5] = rect.size.y
	ornaments_buffer[base + 3] = center.x; ornaments_buffer[base + 7] = center.y
	ornaments_buffer[base + 8] = color.r; ornaments_buffer[base + 9] = color.g
	ornaments_buffer[base + 10] = color.b; ornaments_buffer[base + 11] = color.a
	return index + 1

func _update_people_meshes(delta: float) -> void:
	if not mesh_dirty and not people_animating: return
	mesh_dirty = false; people_animating = false
	var ornaments := 0
	var smoothing := 1.0 - exp(-delta * 16.0)
	for index in render_ids.size():
		var id := render_ids[index]
		var target := render_targets[index]
		var current: Vector2 = person_positions.get(id, target)
		var movement := target - current
		if absf(movement.x) > 0.1: person_directions[id] = signf(movement.x)
		var pos := current.lerp(target, smoothing) if not reduce_motion else target
		var walking := pos.distance_squared_to(target) > 0.01
		if not walking: pos = target
		people_animating = walking or people_animating
		person_positions[id] = pos
		var bob := -absf(sin(visual_time * 14.0 + id)) * 0.8 if walking and not reduce_motion else 0.0
		var scale_value := render_scales[index]
		var facing: float = person_directions.get(id, 1.0)
		var base := index * 12
		people_buffer[base] = scale_value; people_buffer[base + 5] = scale_value
		people_buffer[base + 3] = pos.x; people_buffer[base + 7] = pos.y + (-4 + bob) * scale_value
		people_buffer[base + 8] = float(render_sprites[index]); people_buffer[base + 9] = 1.0
		people_buffer[base + 10] = float(render_palettes[index] + render_hunger[index] * PixelArt.PEOPLE_PALETTES); people_buffer[base + 11] = 1.0 if facing < 0 else 0.0
		if render_elder[index]: ornaments = _ornament(ornaments, Rect2(pos + Vector2(-2, -9 + bob) * scale_value, Vector2(4, 2) * scale_value), Color("e3dfcc"))
		if render_cargo[index]:
			ornaments = _ornament(ornaments, Rect2(pos + Vector2(3 if facing > 0 else -7, -5) * scale_value, Vector2(4, 4) * scale_value), Color("334c40"))
			ornaments = _ornament(ornaments, Rect2(pos + Vector2(4 if facing > 0 else -7, -5) * scale_value, Vector2(3, 3) * scale_value), Color("956945") if render_cargo[index] == 1 else Color("e6c879"))
	people_multimesh.visible_instance_count = render_ids.size()
	ornaments_multimesh.visible_instance_count = ornaments
	if not render_ids.is_empty(): people_multimesh.buffer = people_buffer
	if ornaments > 0: ornaments_multimesh.buffer = ornaments_buffer

func _draw() -> void:
	var started := Time.get_ticks_usec()
	drawn_textures.clear()
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
		var style: Dictionary = town_appearances.get(town.id, {})
		var focus: String = style.get("focus", "mixed")
		draw_rect(Rect2(pos + Vector2(7, -10 + flutter), Vector2(8, 6)), WorldAppearanceJob.COLORS[focus].darkened(0.3))
		if zoom >= 0.8:
			draw_texture_rect(settlement_marks[focus], Rect2(pos + Vector2(8, -10 + flutter), Vector2(6, 6)), false)
			var secondary: String = style.get("secondary", "mixed")
			if secondary != "mixed": draw_rect(Rect2(pos + Vector2(7, -4 + flutter), Vector2(8, 2)), WorldAppearanceJob.COLORS[secondary])
	if zoom >= 0.15:
		for value in world.buildings: _draw_building(value)
	if people_multimesh.visible_instance_count > 0: draw_multimesh(people_multimesh, people_atlas)
	if ornaments_multimesh.visible_instance_count > 0: draw_multimesh(ornaments_multimesh, null)
	if fire_multimesh.visible_instance_count > 0: draw_multimesh(fire_multimesh,fire_atlas)
	_draw_effects()
	_draw_weather()
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
	draw_usec = Time.get_ticks_usec() - started

func _draw_building(value: Dictionary) -> void:
	var cell := Vector2i(value.x, value.y)
	if not Rect2(Vector2.ZERO, size).grow(64).has_point(cell_to_local(cell)): return
	var pos := Vector2(cell - camera_origin) * TILE
	var extent := Vector2.ONE * int(WorldEconomy.SIZE[value.kind]) * TILE
	var style: Dictionary = town_appearances.get(value.town, {})
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
			if style.get("rotation", false) and row % 2 == 1: crop = crop.lerp(Color("9fba7d"), 0.35)
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
	if value.kind == "house": sprite = house_variants[style.get("focus", "mixed") + ":" + str(style.get("form", 0))]
	if idle_furnaces.has(value.kind) and not working_buildings.has(value.id): sprite = idle_furnaces[value.kind]
	draw_rect(Rect2(pos + Vector2(-2, 1), extent + Vector2(4, 3)), Color("bdad84"))
	var sprite_size := Vector2(sprite.get_width(), sprite.get_height())
	var corner := pos + Vector2((extent.x - sprite_size.x) * 0.5, extent.y - sprite_size.y)
	draw_texture_rect(sprite, Rect2(corner, sprite_size), false)
	if zoom >= 0.9:
		var supply := ""
		if value.kind in ["store", "market"] and style.get("food", false): supply = "food"
		elif value.kind in ["forge", "kiln", "workshop"] and style.get("stone", false): supply = "materials"
		elif value.kind in ["port", "dock"] and style.get("wood", false): supply = "maritime"
		if not supply.is_empty(): draw_texture_rect(supplies_textures[supply], Rect2(pos + Vector2(extent.x - 5, extent.y - 4), Vector2(8, 6)), false)

func _draw_brush() -> void:
	var radius := mini(brush_radius, 8) if tool == "fire" else (mini(brush_radius, 8) + 3 if tool == "rain" else (brush_radius if tool.begins_with("biome_") or tool in ["water", "sand", "grass", "forest", "mountain"] else 0))
	var color: Color = TOOL_COLORS.get(tool, Color("e8ba83"))
	if tool == "person" and not world.walkable(hover):
		color = Color("ed9376")
	if tool not in ["inspect", "pan"] and radius <= 12:
		if not brush_masks.has(radius):
			var mask := Image.create(radius*2+1,radius*2+1,false,Image.FORMAT_RGBA8)
			for y in range(-radius,radius+1):
				for x in range(-radius,radius+1):
					if x*x+y*y <= radius*radius: mask.set_pixel(x+radius,y+radius,Color(1,1,1,0.2))
			brush_masks[radius] = ImageTexture.create_from_image(mask)
		draw_texture_rect(brush_masks[radius],Rect2(Vector2(hover-camera_origin-Vector2i.ONE*radius)*TILE,Vector2.ONE*(radius*2+1)*TILE),false,color)
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

func _refresh_weather_effects() -> void:
	var live := {}
	for event in world.weather.active:
		live[int(event.id)] = true
		var strike: int = event.strike_tick
		if strike < 0 or int(weather_strikes.get(event.id, -1)) == strike: continue
		weather_strikes[int(event.id)] = strike
		var cell := Vector2i(event.strike_x, event.strike_y)
		if world.ticks - strike <= 1 and Rect2(Vector2.ZERO, size).has_point(cell_to_local(cell)): add_effect(cell, "fire", 0)
	for id in weather_strikes.keys():
		if not live.has(id): weather_strikes.erase(id)

func _draw_weather() -> void:
	if zoom < 0.35: return
	for event in world.weather.active:
		var cell := Vector2i(event.x, event.y)
		var screen := cell_to_local(cell)
		var radius := float(event.radius * TILE)
		if not Rect2(Vector2.ZERO, size).grow(radius * zoom).has_point(screen): continue
		var center := (Vector2(cell - camera_origin) + Vector2.ONE * 0.5) * TILE
		for drop in 16:
			var angle := drop * 2.399 + float(event.id)
			var distance := sqrt(float(drop) / 16.0) * radius
			var pos := center + Vector2(cos(angle), sin(angle)) * distance
			if event.kind in ["rain", "storm"]:
				pos.y += fmod(visual_time * 24.0 + drop * 3, 12.0) - 6.0
				draw_line(pos, pos + Vector2(-3 if event.kind == "storm" else -1, 5), Color(0.65, 0.82, 0.88, 0.48), 1.0)
			elif event.kind == "frost":
				pos.y += sin(visual_time * 0.6 + drop) * 2.0
				draw_rect(Rect2(pos, Vector2.ONE), Color(0.91, 0.94, 0.86, 0.7))
			elif event.kind == "drought":
				pos.x += sin(visual_time + drop) * 2.0
				draw_line(pos, pos + Vector2(3, 0), Color(0.85, 0.7, 0.43, 0.4), 1.0)
			else:
				draw_rect(Rect2(pos + Vector2(0, -8), Vector2(4, 2)), Color(0.33, 0.42, 0.44, 0.22))

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
		draw_style_box(name_style, rect)
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
	drawn_textures.append(texture)
	draw_texture_rect(texture, rect, false, Color(1, 1, 1, 0.86))
	var ratio := rect.size / (Vector2(minimap_bounds.size) * TILE)
	var visible_rect := Rect2(rect.position + (Vector2(camera_origin - minimap_bounds.position) * TILE - offset / zoom) * ratio, size / zoom * ratio)
	visible_rect = visible_rect.intersection(rect)
	if visible_rect.has_area():
		draw_rect(visible_rect, Color("f3deb0"), false, 1)
	draw_rect(rect.grow(5), Color("9a795f"), false, 1)

func add_effect(cell: Vector2i, kind: String, radius: int = -1) -> void:
	var effect_radius := brush_radius if radius < 0 else radius
	if kind != "person" and visual_time - last_effect_time < 0.07:
		return
	last_effect_time = visual_time
	if effects.size() >= 24:
		effects.pop_front()
	effects.append({"pos": (Vector2(cell - camera_origin) + Vector2.ONE * 0.5) * TILE, "kind": kind,
		"color": TOOL_COLORS.get(kind, Color("f5dfaa")), "age": 0.0,
		"duration": 0.65 if kind == "rain" else 0.35,
		"radius": float((mini(effect_radius, 8) + 3 if kind == "rain" else (mini(effect_radius, 8) + 1 if kind == "fire" else effect_radius + 1)) * TILE)})

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
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION: return
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
				stroke_coverage = {}; stroke_signature.clear()
				if event.pressed:
					apply_tool(hover)
	elif event is InputEventMouseMotion:
		hover = local_to_cell(event.position)
		if panning:
			offset += event.relative
			_clamp_camera()
		elif dragging and (tool.begins_with("biome_") or tool in ["water", "sand", "grass", "forest", "mountain", "fire", "rain"]):
			_paint_segment(last_painted, hover)
	elif event is InputEventScreenTouch:
		if event.pressed:
			hover = local_to_cell(event.position)
			touches[event.index] = event.position
			last_touch = event.position
			if touches.size() == 1:
				touch_painted = false
				last_painted = WorldState.NO_CELL
				stroke_coverage = {}; stroke_signature.clear()
			if touches.size() == 2:
				touch_painted = true
				pinch_distance = _touch_distance()
		else:
			if not event.canceled and touches.has(event.index) and touches.size() == 1 and not touch_painted and tool != "pan":
				apply_tool(local_to_cell(event.position))
			touches.erase(event.index)
			if touches.is_empty(): hover = WorldState.NO_CELL
			pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		var previous: Vector2 = touches[event.index]
		hover = local_to_cell(event.position)
		touches[event.index] = event.position
		if touches.size() >= 2:
			hover = WorldState.NO_CELL
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
		elif tool.begins_with("biome_") or tool in ["water", "sand", "grass", "forest", "mountain", "fire", "rain"]:
			_paint_segment(local_to_cell(previous), local_to_cell(event.position))
			touch_painted = true
	queue_redraw()
	accept_event()

func _touch_distance() -> float:
	var positions := touches.values()
	return positions[0].distance_to(positions[1])

func cancel_input() -> void:
	touches.clear()
	pinch_distance = 0.0
	touch_painted = false
	dragging = false
	panning = false
	last_touch = Vector2.ZERO
	last_painted = WorldState.NO_CELL
	hover = WorldState.NO_CELL
	stroke_coverage = {}; stroke_signature.clear()

func _paint_segment(start: Vector2i, finish: Vector2i) -> void:
	if start == WorldState.NO_CELL: start = finish
	if start == finish and last_painted == finish: return
	_queue_brush(start,finish)
	last_painted = finish

func _queue_brush(start: Vector2i, finish: Vector2i) -> void:
	last_brush_input_usec = Time.get_ticks_usec()
	if not world.inside(start) or not world.inside(finish):
		var origin := Vector2(start)
		var direction := Vector2(finish-start)
		var first := 0.0
		var last := 1.0
		for axis in 2:
			if direction[axis] == 0:
				if origin[axis] < -WorldState.COORD_LIMIT or origin[axis] >= WorldState.COORD_LIMIT: return
				continue
			var a: float = (-WorldState.COORD_LIMIT-origin[axis])/direction[axis]
			var b: float = (WorldState.COORD_LIMIT-1-origin[axis])/direction[axis]
			first = maxf(first,minf(a,b)); last = minf(last,maxf(a,b))
			if first > last: return
		start = Vector2i((origin+direction*first).round())
		finish = Vector2i((origin+direction*last).round())
	var signature := [tool,brush_radius]
	if signature != stroke_signature:
		stroke_signature = signature; stroke_coverage = {}
	if not pending_tools.is_empty():
		var previous: Dictionary = pending_tools.back()
		if previous.get("tool") == tool and previous.get("radius") == brush_radius and previous.get("finish") == start and is_same(previous.get("coverage"),stroke_coverage):
			var a: Vector2i = previous.finish-previous.start
			var b := finish-start
			if a.x*b.y == a.y*b.x and a.x*b.x+a.y*b.y >= 0:
				previous.finish = finish
				return
	pending_tools.append({"start":start,"finish":finish,"tool":tool,"radius":brush_radius,"coverage":stroke_coverage,"previews":brush_previews})

func has_pending_edits() -> bool:
	return brush_job != null or terrain_repair_job != null or not pending_tools.is_empty() or not brush_touched.is_empty() or brush_terrain_dirty or brush_changed

func active_stroke() -> bool:
	return (dragging or (touches.size() == 1 and touch_painted)) and (tool.begins_with("biome_") or tool in ["water","sand","grass","forest","mountain","fire","rain"]) and Time.get_ticks_usec()-last_brush_input_usec < 120000

func apply_tool(cell: Vector2i) -> void:
	if not world.inside(cell) or cell == last_painted: return
	last_painted = cell
	if tool.begins_with("biome_") or tool in ["water","sand","grass","forest","mountain","fire","rain"]:
		_queue_brush(cell,cell)
	elif (world.stepping or edits_locked or has_pending_edits()) and tool != "inspect":
		pending_tools.append({"cell":cell,"tool":tool,"radius":brush_radius})
	else: _apply_tool_now(cell)

func flush_tools(budget_usec: int = 2000) -> void:
	if world.stepping or edits_locked: return
	var started := Time.get_ticks_usec()
	var deadline := started + budget_usec
	while has_pending_edits():
		if terrain_repair_job != null:
			terrain_repair_job.unit()
			if terrain_repair_job.finished: terrain_repair_job = null; brush_terrain_dirty = false
		elif brush_job != null:
			brush_job.unit()
			if brush_job.finished:
				if brush_job.terrain_dirty: brush_repair_checked = false
				brush_changed = brush_changed or brush_job.changed
				brush_terrain_dirty = brush_terrain_dirty or brush_job.terrain_dirty
				brush_cells_written += brush_job.cells_written
				for key in brush_job.touched: brush_touched[key] = true
				if brush_job.rejected: feedback.emit("Достигнут лимит участков или ручных биомов.")
				if brush_job.changed:
					add_effect(brush_job.center,brush_job.mode,brush_job.command.radius)
					if brush_job.mode == "rain": world.wet_until = world.ticks+WorldState.RAIN_TICKS; world.drought_until = 0
					if brush_job.mode in ["fire","rain"]:
						world.site_cache.clear()
						if not brush_job.coverage.has("event"):
							brush_job.coverage.event = true
							world.log_event("Удар молнии" if brush_job.mode == "fire" else "Живительный дождь","Загорелась земля. Дождь может остановить огонь." if brush_job.mode == "fire" else "Огонь погас, запасы еды на земле восстановились.")
				brush_job = null
		elif not pending_tools.is_empty():
			var command: Dictionary = pending_tools.pop_front()
			if command.has("start"): brush_job = WorldBrushJob.new(world,command)
			else:
				var previous_tool := tool; var previous_radius := brush_radius
				tool = command.tool; brush_radius = command.radius
				_apply_tool_now(command.cell)
				tool = previous_tool; brush_radius = previous_radius
		elif not brush_touched.is_empty():
			if brush_terrain_dirty and not brush_repair_needed and not brush_repair_checked:
				brush_repair_needed = WorldTerrainRepairJob.needed(world,brush_touched)
				brush_repair_checked = true
			var key: Vector2i = brush_touched.keys()[0]; brush_touched.erase(key)
			if world.chunks.has(key) and world.chunks[key].tiles.count(WorldState.Terrain.WATER) == WorldState.CHUNK_SIZE*WorldState.CHUNK_SIZE:
				world.chunks.erase(key); world.region_key_count = -1
				world.region_bounds.erase(key); world.bounds_dirty.erase(key)
		elif brush_terrain_dirty:
			if brush_repair_needed: terrain_repair_job = WorldTerrainRepairJob.new(world)
			else: brush_terrain_dirty = false
			brush_repair_needed = false
			brush_repair_checked = false
		elif brush_changed:
			brush_changed = false
			world.regions.trim(world,WorldState.NO_CELL,1)
			world.terrain_changed.emit(); world.changed.emit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	if brush_job != null and brush_job.changed: world.terrain_changed.emit()
	brush_usec = Time.get_ticks_usec()-started

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
