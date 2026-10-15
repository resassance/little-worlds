class_name WorldRegionSnapshot
extends RefCounted

var cache
var metadata: Dictionary

func _init(owner, source: Dictionary) -> void:
	cache = owner
	metadata = source.duplicate()
	cache.retain_snapshot(metadata.path)

func read() -> Dictionary:
	return cache.read_snapshot(metadata)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(cache): cache.release_snapshot(metadata.path)
