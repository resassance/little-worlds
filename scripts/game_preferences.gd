class_name GamePreferences
extends RefCounted
const PATH := "user://preferences.cfg"
var reduce_motion := false
var minimap := false
var effects := 0.35
var ambience := 0.12
var autosave := true
var tutorial_done := false
var ui_scale := 1.0
var first_world_seed := -1

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return
	for key in ["reduce_motion", "minimap", "autosave", "tutorial_done"]:
		var value: Variant = config.get_value("game", key, get(key))
		if value is bool: set(key, value)
	for key in ["effects", "ambience"]:
		var value: Variant = config.get_value("game", key, get(key))
		if (value is float or value is int) and is_finite(float(value)): set(key, clampf(value,0,1))

	var saved_seed: Variant = config.get_value("game","first_world_seed",-1)
	if saved_seed is int and saved_seed>=0 and saved_seed<=2147483647: first_world_seed = saved_seed
	var interface_scale: Variant = config.get_value("game","ui_scale",1.0)
	if (interface_scale is float or interface_scale is int) and is_finite(float(interface_scale)):
		ui_scale = clampf(float(interface_scale),0.85,1.3)

func save_preferences() -> Error:
	var config := ConfigFile.new()
	for key in ["reduce_motion", "minimap", "effects", "ambience", "autosave", "tutorial_done", "ui_scale", "first_world_seed"]: config.set_value("game",key,get(key))
	return config.save(PATH)

func initial_seed() -> int:
	if first_world_seed<0:
		var source := RandomNumberGenerator.new()
		source.randomize()
		first_world_seed = source.randi_range(1,2147483647)
		save_preferences()
	return first_world_seed
