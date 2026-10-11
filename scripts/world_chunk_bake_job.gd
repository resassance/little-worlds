class_name WorldChunkBakeJob
extends RefCounted

const TILE := WorldView.TILE
const HALO := WorldView.HALO
const COLORS := WorldView.COLORS
var world: WorldState
var coord: Vector2i
var detailed: bool
var revision: int
var image: Image
var shores: Array[Vector2i] = []
var render_width: int
var render_height: int
var render_origin: Vector2i
var render_tiles := PackedInt32Array()
var depths := PackedInt32Array()
var frontier: Array[int] = []
var head := 0
var cursor := 0
var phase := -1
var source_keys: Array[Vector2i] = []
var source_cursor := 0
var finished := false
var noise := FastNoiseLite.new()
var tree: Image
var pine: Image
var autumn: Image
var peak: Image
var source_tiles: Dictionary = {}

func _init(value: WorldState, key: Vector2i, detail: bool) -> void:
	world = value; coord = key; detailed = detail
	revision = world.revisions.get(coord, 0)
	render_width = WorldState.CHUNK_SIZE + (HALO * 2 if detailed else 0)
	render_height = render_width
	render_origin = coord * WorldState.CHUNK_SIZE - (Vector2i(HALO, HALO) if detailed else Vector2i.ZERO)
	for dy in range(-1,2) if detailed else [0]:
		for dx in range(-1,2) if detailed else [0]:
			var region := coord + Vector2i(dx,dy)
			if world.has_region(region): source_keys.append(region)
	image = Image.create(render_width * (TILE if detailed else 1), render_height * (TILE if detailed else 1), false, Image.FORMAT_RGBA8)
	depths.resize(render_width * render_height); depths.fill(999)
	noise.seed = world.world_seed + 101
	noise.frequency = 0.14
	tree = PixelArt.sprite_image(PixelArt.TREE, {"o": Color("3e6548")})
	pine = PixelArt.sprite_image(PixelArt.PINE, {"o": Color("385d46")})
	autumn = PixelArt.sprite_image(PixelArt.TREE, {"o": Color("4b6a44"), "l": Color("b6b36b"), "g": Color("9a9e59"), "d": Color("687c48")})
	peak = PixelArt.sprite_image(PixelArt.PEAK)

func advance(budget_usec: int = 1500) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished:
		_unit()
		if budget_usec > 0 and Time.get_ticks_usec() >= deadline: break
	return finished

func _unit() -> void:
	match phase:
		-1:
			if source_cursor < source_keys.size():
				var region := source_keys[source_cursor]; source_cursor += 1
				var chunk := world.regions.get_region(world, region)
				if not chunk.is_empty(): source_tiles[region] = chunk.tiles
			else: phase = 0
		0:
			for x in render_width:
				var cell := render_origin + Vector2i(x,cursor)
				var region := WorldState.chunk_of(cell)
				var terrain: int = source_tiles[region][posmod(cell.y,WorldState.CHUNK_SIZE)*WorldState.CHUNK_SIZE+posmod(cell.x,WorldState.CHUNK_SIZE)] if source_tiles.has(region) else WorldState.Terrain.WATER
				var index := render_tiles.size()
				render_tiles.append(terrain)
				if terrain != WorldState.Terrain.WATER:
					depths[index] = 0; frontier.append(index)
				if not detailed: image.set_pixel(x, cursor, _color(terrain, cell))
			cursor += 1
			if cursor == render_height:
				phase = 1 if detailed else 4; cursor = 0
		1:
			if head >= frontier.size(): phase = 2; return
			var index := frontier[head]; head += 1
			if depths[index] >= 7: return
			var cell := Vector2i(index % render_width, index / render_width)
			for direction in WorldState.DIRECTIONS:
				var other: Vector2i = cell + direction
				if other.x >= 0 and other.y >= 0 and other.x < render_width and other.y < render_height:
					var ni := other.y * render_width + other.x
					if depths[ni] > depths[index] + 1:
						depths[ni] = depths[index] + 1; frontier.append(ni)
		2:
			_pixels(cursor); cursor += 1
			if cursor == render_height: phase = 3; cursor = 0
		3:
			_sprites(cursor); cursor += 1
			if cursor == render_height: phase = 4
		4:
			finished = true

func _pixels(y: int) -> void:
	for x in render_width:
		var cell := Vector2i(x, y)
		var idx := (cell.y * render_width + cell.x)
		var terrain: int = render_tiles[idx]
		var px := x * TILE
		var py := y * TILE
		var detail := posmod(hash(Vector3i(x + render_origin.x, y + render_origin.y, world.world_seed)), 997)
		var variation := noise.get_noise_2d(x + render_origin.x, y + render_origin.y) * 0.06
		var color := _color(terrain, cell + render_origin)
		if terrain == WorldState.Terrain.WATER:
			var water_colors := [Color("78b4ab"), Color("5e9c9e"), Color("43808b"), Color("356b7d"), Color("2e6477"), COLORS[0]]
			color = water_colors[mini(depths[idx] - 1, water_colors.size() - 1)]
			variation *= 0.22
		color = color.lightened(variation) if variation > 0 else color.darkened(-variation)
		image.fill_rect(Rect2i(px, py, TILE, TILE), color)
		match terrain:
			WorldState.Terrain.WATER:
				if detail % 59 == 0:
					image.fill_rect(Rect2i(px + 1, py + 4, 5, 1), color.lightened(0.09))
				if depths[idx] == 1:
					for direction in WorldState.DIRECTIONS:
						var neighbor: Vector2i = cell + direction
						if (neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < render_width and neighbor.y < render_height) and render_tiles[(neighbor.y * render_width + neighbor.x)] != WorldState.Terrain.WATER:
							var edge := Rect2i(px, py, TILE, 1)
							if direction == Vector2i.DOWN: edge = Rect2i(px, py + TILE - 1, TILE, 1)
							if direction == Vector2i.LEFT: edge = Rect2i(px, py, 1, TILE)
							if direction == Vector2i.RIGHT: edge = Rect2i(px + TILE - 1, py, 1, TILE)
							image.fill_rect(edge, Color("b9d8bc"))
					if detail % 7 == 0 and x >= HALO and y >= HALO and x < render_width - HALO and y < render_height - HALO:
						shores.append(cell + render_origin)
			WorldState.Terrain.SAND:
				if detail % 5 == 0:
					image.fill_rect(Rect2i(px + 3, py + 4, 2, 1), Color("c9b68b"))
			WorldState.Terrain.GRASS, WorldState.Terrain.FOREST:
				if detail % 7 == 0:
					image.fill_rect(Rect2i(px + 2, py + 3, 1, 2), color.darkened(0.14))
					image.set_pixel(px + 3, py + 4, color.lightened(0.08))
				if terrain == WorldState.Terrain.GRASS and detail % 31 == 0:
					image.set_pixel(px + 5, py + 3, Color("f2da99"))
					image.set_pixel(px + 6, py + 4, Color("e8b796"))
			WorldState.Terrain.MOUNTAIN:
				var north := cell + Vector2i.UP
				var south := cell + Vector2i.DOWN
				if (north.x >= 0 and north.y >= 0 and north.x < render_width and north.y < render_height) and render_tiles[(north.y * render_width + north.x)] != terrain:
					image.fill_rect(Rect2i(px, py, TILE, 2), Color("bdc2a4"))
				if (south.x >= 0 and south.y >= 0 and south.x < render_width and south.y < render_height) and render_tiles[(south.y * render_width + south.x)] != terrain:
					image.fill_rect(Rect2i(px, py + 5, TILE, 3), Color("6e7d6a"))
				if detail % 9 == 0:
					image.fill_rect(Rect2i(px + 2, py + 4, 3, 1), Color("828d7c"))

func _sprites(y: int) -> void:
	for x in render_width:
		var terrain := render_tiles[y * render_width + x]
		var detail := posmod(hash(Vector3i(x + render_origin.x, y + render_origin.y, world.world_seed)), 997)
		if terrain == WorldState.Terrain.FOREST and detail % 4 == 0 and world.building_at(render_origin + Vector2i(x, y)).is_empty():
			var sprite := tree if detail % 5 != 0 else pine
			if detail % 17 == 0: sprite = autumn
			var biome:=WorldClimate.biome(world,render_origin+Vector2i(x,y))
			if biome>=3: sprite=pine
			image.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), Vector2i(x * TILE - 2, y * TILE - 7))
		elif terrain == WorldState.Terrain.MOUNTAIN and detail % 13 == 0:
			image.blend_rect(peak, Rect2i(Vector2i.ZERO, peak.get_size()), Vector2i(x * TILE - 4, y * TILE - 3))

func _color(terrain: int, cell: Vector2i) -> Color:
	var color: Color = COLORS[terrain]
	if terrain in [WorldState.Terrain.GRASS, WorldState.Terrain.FOREST]:
		var biome := WorldClimate.biome(world, cell)
		if biome != 0: color = WorldClimate.COLORS[biome].darkened(0.12 if terrain == WorldState.Terrain.FOREST else 0.0)
		if biome in [0, 3, 4, 5]: color.a = 250.0 / 255.0
	return color
