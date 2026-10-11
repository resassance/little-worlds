class_name WorldBuildingRepairJob
extends RefCounted

var world
var cursor := 0
var phase := 0
var lost_stores: Dictionary = {}
var was_active := false
var finished := false

func _init(value) -> void:
	world = value
	was_active = world.workforce.active
	world.workforce.begin(world)
	cursor = world.buildings.size() - 1

func unit() -> void:
	if finished: return
	match phase:
		0:
			if cursor >= 0: world.repair_building(cursor, lost_stores); cursor -= 1
			else: phase = 1; cursor = 0
		1:
			if cursor < world.towns.size(): world.repair_storage(world.towns[cursor], lost_stores); cursor += 1
			else: phase = 2; cursor = 0
		2:
			if cursor < world.towns.size():
				var home: Dictionary = world.towns[cursor]; cursor += 1
				if WorldEconomy.count(world, home, "camp") == 0:
					var cell := Vector2i(home.x, home.y)
					if world.walkable(cell) and not world.fires.has(cell): WorldEconomy.add_building(world, home, "camp", cell, true)
			else:
				if not was_active: world.workforce.end()
				WorldSociety.invalidate(world)
				finished = true
