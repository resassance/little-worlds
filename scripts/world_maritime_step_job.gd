class_name WorldMaritimeStepJob
extends RefCounted

var world
var ships: Array
var cursor := 0
var phase := 0
var route_cursor := 1
var ship: Dictionary = {}
var segment: WorldSeaSegmentJob
var route: WorldSeaRouteJob
var finished := false

func _init(value) -> void:
	world = value
	ships = world.voyages.duplicate()

func _next_ship() -> void:
	cursor += 1; phase = 0; route_cursor = 1
	segment = null; route = null

func unit() -> void:
	if finished: return
	if cursor >= ships.size(): finished = true; return
	ship = ships[cursor]
	match phase:
		0:
			if ship.phase in ["unload", "boarding"] or ship.crew.is_empty() or world.voyage_route_versions.get(ship.id, -1) == world.sea_revision: phase = 3; return
			world.voyage_route_versions[ship.id] = world.sea_revision
			phase = 1
		1:
			if route_cursor >= ship.route.size(): phase = 3; return
			if segment == null: segment = WorldSeaSegmentJob.new(world, Vector2i(ship.route[route_cursor - 1][0], ship.route[route_cursor - 1][1]), Vector2i(ship.route[route_cursor][0], ship.route[route_cursor][1]))
			if not segment.finished: segment.unit(); return
			if segment.clear: route_cursor += 1; segment = null; return
			var current := WorldMaritime.position(ship)
			if world.terrain_at(current) != WorldState.Terrain.WATER: WorldMaritime.lose(world, ship); _next_ship(); return
			var destination: Array = ship.route.back() if ship.phase == "outbound" else ship.route.front()
			route = WorldSeaRouteJob.new(world, current, Vector2i(destination[0], destination[1])); phase = 2
		2:
			if not route.finished: route.unit(); return
			if route.result.is_empty(): WorldMaritime.lose(world, ship); _next_ship(); return
			var changed := route.result
			if ship.phase == "returning": changed.reverse()
			ship.route = changed; ship.progress = 0
			ship.duration = maxi(20, ceili(WorldMaritime.route_length(changed) / int(WorldMaritime.SPEED[ship.kind])))
			world.log_event("Изменён курс", "Мореплаватели обошли новую сушу. Дальнейший путь зависит от оставшихся запасов.")
			phase = 3
		3:
			WorldMaritime.step_ship(world, ship)
			_next_ship()
