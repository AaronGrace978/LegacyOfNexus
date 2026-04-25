class_name BuddyCatalog
extends RefCounted

const BattlePartyMemberScript := preload("res://scripts/battle/battle_party_member.gd")

const DATA_PATH := "res://data/buddies/buddy_definitions.json"
const DEFAULT_PARTY_SIZE := 6
const DEFAULT_BATTLE_VISUAL_SCENE := "res://scenes/buddies/sparklet_buddy_visual.tscn"
const DEFAULT_SHADE_VISUAL_SCENE := "res://scenes/buddies/shade_enemy_visual.tscn"
const DEFAULT_PRIMARY_COLOR := Color(0.45, 0.95, 1.0, 1.0)
const DEFAULT_ACCENT_COLOR := Color(0.85, 1.0, 1.0, 1.0)
const DEFAULT_MAX_HEALTH := 18
const DEFAULT_ATTACK_POWER := 4
const DEFAULT_LEVEL := 3

const DEFAULT_MOVES := [
	{
		"id": "strike",
		"label": "Strike",
		"kind": "single",
		"power_mult": 1.0,
		"requires_partner": false,
	},
	{
		"id": "surge",
		"label": "Surge",
		"kind": "single",
		"power_mult": 1.65,
		"requires_partner": false,
	},
]

static var _cached_data: Dictionary = {}


static func get_buddy_definition(unit_name: String) -> Dictionary:
	var key := unit_name.strip_edges()
	return _dictionary_from_value(_get_buddy_map().get(key, {})).duplicate(true)


static func has_definition(unit_name: String) -> bool:
	return not get_buddy_definition(unit_name).is_empty()


static func get_move_entries(unit_name: String) -> Array:
	var definition := get_buddy_definition(unit_name)
	var raw_entries := _array_from_value(definition.get("moves", []))
	if raw_entries.is_empty():
		return _duplicate_move_entries(DEFAULT_MOVES)
	return _duplicate_move_entries(raw_entries)


static func get_move_entry_by_id(unit_name: String, move_id: String) -> Dictionary:
	for entry: Variant in get_move_entries(unit_name):
		if str((entry as Dictionary).get("id", "")) == move_id:
			return (entry as Dictionary).duplicate(true)
	return {}


static func get_palette(unit_name: String) -> Dictionary:
	var definition := get_buddy_definition(unit_name)
	var palette := _dictionary_from_value(definition.get("palette", {}))
	return {
		"primary": _color_from_value(palette.get("primary", []), DEFAULT_PRIMARY_COLOR),
		"accent": _color_from_value(palette.get("accent", []), DEFAULT_ACCENT_COLOR),
	}


static func get_visual_scene_path(unit_name: String, purpose: String = "battle") -> String:
	var definition := get_buddy_definition(unit_name)
	if purpose == "overworld_follower":
		var follower_path := str(definition.get("overworld_follower_visual_scene", "")).strip_edges()
		if follower_path != "":
			return follower_path

	var battle_path := str(definition.get("battle_visual_scene", "")).strip_edges()
	if battle_path != "":
		return battle_path

	var key := unit_name.strip_edges()
	if key.ends_with("Shade") or key.contains("Shade"):
		return DEFAULT_SHADE_VISUAL_SCENE
	return DEFAULT_BATTLE_VISUAL_SCENE


static func build_party_member(
	unit_name: String,
	party_index: int = 0,
	profile_name: String = "party_member",
	locked_override: bool = false
):
	var display_name := unit_name.strip_edges()
	var definition := get_buddy_definition(display_name)
	var profile := _resolve_profile(definition, profile_name)
	var palette := get_palette(display_name)
	var max_health: int = max(1, int(profile.get("max_health", DEFAULT_MAX_HEALTH)))
	var attack_power: int = max(1, int(profile.get("attack_power", DEFAULT_ATTACK_POWER)))
	var level: int = max(1, int(profile.get("level", DEFAULT_LEVEL)))
	var locked := bool(profile.get("locked", false)) or locked_override
	return BattlePartyMemberScript.new(
		party_index,
		display_name if display_name != "" else "Buddy",
		max_health,
		attack_power,
		palette["primary"],
		palette["accent"],
		locked,
		level
	)


static func build_captured_member(unit_name: String):
	return build_party_member(unit_name, 0, "capture_member")


static func build_default_party() -> Array:
	var roster: Array = []
	var default_party := _array_from_value(_get_data().get("default_party", []))
	for index in range(DEFAULT_PARTY_SIZE):
		if index >= default_party.size():
			roster.append(null)
			continue

		var row := _dictionary_from_value(default_party[index])
		var unit_name := str(row.get("name", "")).strip_edges()
		if unit_name == "":
			roster.append(null)
			continue

		roster.append(build_party_member(unit_name, index, "party_member", bool(row.get("locked", false))))

	return roster


static func build_enemy_stats(entry: Dictionary) -> Dictionary:
	var display_name: String = str(entry.get("name", "Buddy")).strip_edges()
	var level: int = clampi(int(entry.get("level", DEFAULT_LEVEL)), 1, 99)
	var encounter_stats := _dictionary_from_value(get_buddy_definition(display_name).get("encounter_stats", {}))
	var palette := get_palette(display_name)
	var max_health: int = max(
		1,
		int(round(float(encounter_stats.get("base_health", 14.0)) + float(level) * float(encounter_stats.get("health_per_level", 3.0))))
	)
	var attack_power: int = max(
		1,
		int(encounter_stats.get("base_attack", 2)) + int(round(float(level) * float(encounter_stats.get("attack_per_level", 0.55))))
	)

	if encounter_stats.has("max_health"):
		max_health = max(1, int(encounter_stats.get("max_health", max_health)))
	if encounter_stats.has("attack_power"):
		attack_power = max(1, int(encounter_stats.get("attack_power", attack_power)))

	return {
		"name": display_name if display_name != "" else "Buddy",
		"max_health": max_health,
		"current_health": max_health,
		"attack_power": attack_power,
		"primary_color": palette["primary"],
		"accent_color": palette["accent"],
		"level": level,
	}


static func _get_data() -> Dictionary:
	if _cached_data.is_empty():
		_cached_data = _load_data()
	return _cached_data


static func _load_data() -> Dictionary:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		printerr("BuddyCatalog: failed to open %s" % DATA_PATH)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("BuddyCatalog: expected dictionary data in %s" % DATA_PATH)
		return {}

	return parsed as Dictionary


static func _get_buddy_map() -> Dictionary:
	return _dictionary_from_value(_get_data().get("buddies", {}))


static func _resolve_profile(definition: Dictionary, profile_name: String) -> Dictionary:
	var profile := _dictionary_from_value(definition.get(profile_name, {}))
	if profile.is_empty() and profile_name != "party_member":
		profile = _dictionary_from_value(definition.get("party_member", {}))
	return profile


static func _duplicate_move_entries(entries: Array) -> Array:
	var duplicates: Array = []
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			duplicates.append((entry as Dictionary).duplicate(true))
	return duplicates


static func _dictionary_from_value(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}


static func _array_from_value(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	return []


static func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Array:
		var raw: Array = value as Array
		if raw.size() >= 3:
			return Color(
				float(raw[0]),
				float(raw[1]),
				float(raw[2]),
				float(raw[3]) if raw.size() > 3 else 1.0
			)
	return fallback
