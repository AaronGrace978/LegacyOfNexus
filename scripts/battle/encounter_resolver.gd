extends RefCounted
class_name EncounterResolver

const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")


static func build_enemy_stats(entry: Dictionary) -> Dictionary:
	return BuddyCatalog.build_enemy_stats(entry)
