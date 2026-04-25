extends Node

signal party_changed

const BattlePartyMemberScript := preload("res://scripts/battle/battle_party_member.gd")
const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")
const PARTY_SIZE := 6

var party_slots: Array = []
var active_battle_partner_index := 1


func _ready() -> void:
	_initialize_default_party()


func _initialize_default_party() -> void:
	if not party_slots.is_empty():
		return

	party_slots = BuddyCatalog.build_default_party()
	active_battle_partner_index = 1


func get_party_snapshot() -> Array:
	var snapshot: Array = []
	for slot in _get_normalized_party():
		snapshot.append(_clone_member(slot))
	return snapshot


func get_party_for_display() -> Array[Dictionary]:
	var display_data: Array[Dictionary] = []
	for index in range(PARTY_SIZE):
		var member = _get_normalized_party()[index]
		if member == null:
			display_data.append({
				"index": index,
				"empty": true,
				"label": "Empty Slot",
			})
			continue

		display_data.append({
			"index": index,
			"empty": false,
			"name": member.unit_name,
			"hp": member.current_health,
			"max_hp": member.max_health,
			"level": member.level,
			"locked": member.locked,
			"primary_color": member.primary_color,
			"accent_color": member.accent_color,
		})
	return display_data


func get_active_battle_partner_index() -> int:
	_ensure_locked_dino_slot()
	active_battle_partner_index = _resolve_active_partner_index(active_battle_partner_index)
	return active_battle_partner_index


func save_party_snapshot(updated_party: Array, preferred_partner_index: int) -> void:
	var normalized_party: Array = []
	for index in range(PARTY_SIZE):
		var member = updated_party[index] if index < updated_party.size() else null
		normalized_party.append(_clone_member(member))

	party_slots = normalized_party
	_ensure_locked_dino_slot()
	active_battle_partner_index = _resolve_active_partner_index(preferred_partner_index)
	emit_signal("party_changed")


func get_save_data() -> Dictionary:
	var slots: Array = []
	for member in _get_normalized_party():
		slots.append(_member_to_save_dict(member))
	return {
		"active_battle_partner_index": get_active_battle_partner_index(),
		"slots": slots,
	}


func load_from_save_data(save_data: Dictionary) -> void:
	var raw_slots: Array = []
	var incoming: Variant = save_data.get("slots", [])
	if typeof(incoming) == TYPE_ARRAY:
		raw_slots = incoming as Array

	party_slots = []
	for index in range(PARTY_SIZE):
		var member_data: Variant = raw_slots[index] if index < raw_slots.size() else null
		party_slots.append(_member_from_save_dict(member_data, index))

	_ensure_locked_dino_slot()
	active_battle_partner_index = _resolve_active_partner_index(int(save_data.get("active_battle_partner_index", active_battle_partner_index)))
	emit_signal("party_changed")


func try_add_captured_buddy(member) -> int:
	if member == null:
		return -1

	var normalized_party := _get_normalized_party()
	for index in range(PARTY_SIZE):
		var existing = normalized_party[index]
		if existing != null:
			continue
		if index == 0:
			continue

		var placed = _clone_member(member)
		if placed == null:
			return -1

		placed.party_index = index
		placed.locked = false
		party_slots[index] = placed
		emit_signal("party_changed")
		return index

	return -1


func _get_normalized_party() -> Array:
	while party_slots.size() < PARTY_SIZE:
		party_slots.append(null)

	if party_slots.size() > PARTY_SIZE:
		party_slots = party_slots.slice(0, PARTY_SIZE)

	_ensure_locked_dino_slot()
	return party_slots


func _ensure_locked_dino_slot() -> void:
	if party_slots.is_empty() or party_slots[0] == null:
		if party_slots.is_empty():
			party_slots.resize(PARTY_SIZE)
		party_slots[0] = BuddyCatalog.build_party_member("Dino Buddy", 0, "party_member", true)

	party_slots[0].locked = true
	party_slots[0].party_index = 0


func _resolve_active_partner_index(preferred_partner_index: int) -> int:
	var normalized_party := _get_normalized_party()
	if preferred_partner_index > 0 and preferred_partner_index < normalized_party.size():
		var preferred_member = normalized_party[preferred_partner_index]
		if preferred_member != null and preferred_member.current_health > 0:
			return preferred_partner_index

	for index in range(1, normalized_party.size()):
		var member = normalized_party[index]
		if member != null and member.current_health > 0:
			return index

	return -1


func _clone_member(member):
	if member == null:
		return null

	var clone = BattlePartyMemberScript.new(
		member.party_index,
		member.unit_name,
		member.max_health,
		member.attack_power,
		member.primary_color,
		member.accent_color,
		member.locked,
		member.level
	)
	clone.current_health = member.current_health
	return clone


func _member_to_save_dict(member) -> Variant:
	if member == null:
		return null
	return {
		"party_index": int(member.party_index),
		"unit_name": str(member.unit_name),
		"max_health": int(member.max_health),
		"current_health": int(member.current_health),
		"attack_power": int(member.attack_power),
		"primary_color": _color_to_array(member.primary_color),
		"accent_color": _color_to_array(member.accent_color),
		"locked": bool(member.locked),
		"level": int(member.level),
	}


func _member_from_save_dict(value: Variant, slot_index: int):
	if typeof(value) != TYPE_DICTIONARY:
		return null

	var data := value as Dictionary
	var member = BattlePartyMemberScript.new(
		slot_index,
		str(data.get("unit_name", "Buddy")),
		max(1, int(data.get("max_health", 20))),
		max(1, int(data.get("attack_power", 4))),
		_color_from_variant(data.get("primary_color", []), Color.WHITE),
		_color_from_variant(data.get("accent_color", []), Color(0.9, 0.9, 0.9, 1.0)),
		bool(data.get("locked", false)),
		max(1, int(data.get("level", 1)))
	)
	member.current_health = clampi(int(data.get("current_health", member.max_health)), 0, member.max_health)
	member.party_index = slot_index
	return member


func _color_to_array(color: Color) -> Array:
	return [color.r, color.g, color.b, color.a]


func _color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Array:
		var raw := value as Array
		if raw.size() >= 3:
			return Color(
				float(raw[0]),
				float(raw[1]),
				float(raw[2]),
				float(raw[3]) if raw.size() > 3 else 1.0
			)
	return fallback
