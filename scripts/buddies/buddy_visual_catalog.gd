extends RefCounted

const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")

static var _scene_cache: Dictionary = {}


static func resolve_battle_visual(unit_name: String) -> PackedScene:
	return _load_scene_from_path(BuddyCatalog.get_visual_scene_path(unit_name, "battle"))


static func resolve_overworld_follower_visual(unit_name: String) -> PackedScene:
	return _load_scene_from_path(BuddyCatalog.get_visual_scene_path(unit_name, "overworld_follower"))


static func _load_scene_from_path(scene_path: String) -> PackedScene:
	var normalized_path := scene_path.strip_edges()
	if normalized_path == "":
		return null
	if _scene_cache.has(normalized_path):
		return _scene_cache[normalized_path] as PackedScene

	var loaded: Resource = load(normalized_path)
	if loaded is PackedScene:
		_scene_cache[normalized_path] = loaded
		return loaded as PackedScene

	return null
