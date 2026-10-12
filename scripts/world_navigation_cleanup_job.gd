class_name WorldNavigationCleanupJob
extends RefCounted

var navigation: Dictionary
var towns: Array
var town_cursor := 0
var data: Dictionary = {}
var fields: Array = []
var field_cursor := 0
var keys: Array = []
var key_cursor := 0
var finished := false
var loaded := false

func _init(value: Dictionary) -> void:
	navigation = value; towns = value.keys()

func unit() -> void:
	if finished: return
	if not loaded:
		if town_cursor >= towns.size(): finished = true; return
		data = navigation[towns[town_cursor]]; loaded = true
		fields = data.keys(); field_cursor = 0; keys.clear(); key_cursor = 0
		return
	if field_cursor >= fields.size():
		navigation.erase(towns[town_cursor]); town_cursor += 1; data = {}; loaded = false; return
	var field = fields[field_cursor]
	if data[field] is Dictionary:
		if keys.is_empty(): keys = data[field].keys(); key_cursor = 0
		if key_cursor < keys.size(): data[field].erase(keys[key_cursor]); key_cursor += 1; return
	data.erase(field); field_cursor += 1; keys.clear(); key_cursor = 0
