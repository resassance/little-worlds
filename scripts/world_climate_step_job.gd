class_name WorldClimateStepJob
extends RefCounted

var world
var cells: Array = []
var cursor := 0
var dirty := false
var finished := false

func _init(value) -> void:
	world = value
	if world.ticks % WorldEconomy.DAY_TICKS == 0 and world.climate.forest_regrowth: cells = world.stumps.keys()

func unit() -> void:
	if finished: return
	if cursor < cells.size():
		dirty = WorldClimate.regrow(world, cells[cursor]) or dirty
		cursor += 1
	else:
		if dirty: world.terrain_changed.emit()
		finished = true
