class_name GamePreferences
extends RefCounted
const PATH := "user://preferences.cfg"
var reduce_motion := false
var minimap := false
var effects := 0.35
var ambience := 0.12
var autosave := true
var tutorial_done := false

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return
	for key in ["reduce_motion", "minimap", "autosave", "tutorial_done"]:
		var value: Variant = config.get_value("game", key, get(key))
		if value is bool: set(key, value)
	for key in ["effects", "ambience"]:
		var value: Variant = config.get_value("game", key, get(key))
		if (value is float or value is int) and is_finite(float(value)): set(key, clampf(value,0,1))

func save_preferences() -> Error:
	var config := ConfigFile.new()
	for key in ["reduce_motion", "minimap", "effects", "ambience", "autosave", "tutorial_done"]: config.set_value("game",key,get(key))
	return config.save(PATH)
